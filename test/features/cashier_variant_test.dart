import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';
import 'package:kagoem_pos_mobile/core/config/app_config.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/held_carts_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/cart_controller.dart';

import '../data/catalog_repository_test.dart' show page;
import '../helpers/fake_backend.dart';
import '../helpers/test_app.dart';
import 'checkout/checkout_controller_test.dart' show kopi, saleJson, waitUntil;

/// The pos-cashier build (flavor `cashier`, e.g. Warung Epon) talks to the
/// single-store predecessor of the SaaS backend: same API, no tenancy, no
/// sales date filter, no idempotency.
void main() {
  group('config', () {
    test('flavor selects the variant and its defaults', () {
      final saas = AppConfig.parse(envName: 'production', baseUrl: 'https://a.b/api/v1', flavor: 'saas');
      expect(saas.multiTenant, isTrue);
      expect(saas.salesDateFilter, isTrue);
      expect(saas.appName, 'Kagoem POS');

      final cashier = AppConfig.parse(envName: 'production', baseUrl: 'https://a.b/api/v1', flavor: 'cashier');
      expect(cashier.multiTenant, isFalse);
      expect(cashier.salesDateFilter, isFalse);
      expect(cashier.appName, 'Warung Epon');
    });

    test('env values override defaults (e.g. after porting the date filter)', () {
      final c = AppConfig.parse(
        envName: 'production',
        baseUrl: 'https://warung-epon.kagoemdev.my.id/api/v1',
        flavor: 'cashier',
        appName: 'Toko Sejahtera',
        salesDateFilter: 'true',
      );
      expect(c.appName, 'Toko Sejahtera');
      expect(c.salesDateFilter, isTrue);
    });

    test('no flavor (plain flutter test/run) means saas; unknown flavors fail', () {
      expect(AppConfig.parse(envName: 'development', baseUrl: 'http://x.y').variant, AppVariant.saas);
      expect(() => AppConfig.parse(envName: 'development', baseUrl: 'http://x.y', flavor: 'kasir'),
          throwsA(isA<ConfigException>()));
    });
  });

  group('single-store session', () {
    late TestHarness h;
    late ProviderContainer c;

    setUp(() async {
      h = TestHarness(config: cashierConfig);
      h.backend.reply('POST', '/auth/login', 200, ok({'user': userJson(), 'token': '5|tok'}));
      h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
      h.backend.reply('POST', '/auth/logout', 200, ok(null));
      c = h.container();
      c.listen(sessionControllerProvider, (_, _) {});
      await waitUntil(c, () => c.read(sessionControllerProvider).status == SessionStatus.unauthenticated);
    });

    tearDown(() => c.dispose());

    test('login goes straight to ready: no /tenants, no X-Tenant-ID', () async {
      await c.read(sessionControllerProvider.notifier).login(email: 'siti@toko.id', password: 'p');

      final state = c.read(sessionControllerProvider);
      expect(state.status, SessionStatus.ready);
      expect(state.activeTenant?.name, 'Warung Epon');
      expect(state.canSwitchTenant, isFalse);
      expect(h.backend.calls('GET', '/tenants'), isEmpty);

      h.backend.reply('GET', '/products', 200, page([]));
      await c.read(sessionControllerProvider.notifier).restore();
      for (final r in h.backend.requests) {
        expect(r.headers.containsKey('X-Tenant-ID'), isFalse, reason: r.uri.path);
      }
      expect(h.store.values.containsKey('kagoem.session.tenant_id'), isFalse);
    });

    test('a user without manage-sales is still denied', () async {
      h.backend.reply('POST', '/auth/login', 200, ok({
        'user': userJson(roles: ['Gudang'], permissions: ['manage-inventory']),
        'token': '5|tok',
      }));
      await c.read(sessionControllerProvider.notifier).login(email: 'g@toko.id', password: 'p');
      expect(c.read(sessionControllerProvider).status, SessionStatus.accessDenied);
    });

    test('held carts work and are scoped to the store and cashier', () async {
      await c.read(sessionControllerProvider.notifier).login(email: 'siti@toko.id', password: 'p');
      c.listen(cartControllerProvider, (_, _) {});
      c.listen(heldCartsControllerProvider, (_, _) {});
      await c.read(heldCartsControllerProvider.future);

      c.read(cartControllerProvider.notifier).add(kopi);
      await c.read(heldCartsControllerProvider.notifier).hold(note: 'Meja 1');
      expect(h.deviceStore.values.keys, contains('kagoem.held_carts.t0.u7'));
    });
  });

  testWidgets('Warung Epon: store name on login and dashboard, history without date filter', (tester) async {
    final h = TestHarness(config: cashierConfig);
    h.backend.reply('POST', '/auth/login', 200, ok({'user': userJson(), 'token': '5|tok'}));
    h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
    h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
    h.backend.reply('GET', '/sales', 200, page([saleJson(withClientReferenceKey: false)]));
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();

    expect(find.text('Warung Epon · Aplikasi Kasir'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-email')), 'siti@toko.id');
    await tester.enterText(find.byKey(const Key('login-password')), 'p');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Toko'), findsOneWidget);
    expect(find.text('Warung Epon'), findsOneWidget);
    expect(find.text('Perusahaan'), findsNothing);

    final menu = find.widgetWithText(InkWell, 'Transaksi');
    await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Hari ini'), findsNothing);
    expect(find.text('TX-261003-00001'), findsOneWidget);
    final q = h.backend.calls('GET', '/sales').last.uri.queryParameters;
    expect(q.containsKey('date_from'), isFalse);
    expect(q.containsKey('date_to'), isFalse);
  });
}
