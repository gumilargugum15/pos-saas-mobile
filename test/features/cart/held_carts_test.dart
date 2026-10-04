import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';
import 'package:kagoem_pos_mobile/core/error/app_failure.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/data/models/catalog_models.dart';
import 'package:kagoem_pos_mobile/domain/entities/party.dart';
import 'package:kagoem_pos_mobile/domain/entities/product.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/cart_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/held_carts_controller.dart';
import 'package:kagoem_pos_mobile/features/checkout/application/checkout_controller.dart';

import '../../data/catalog_repository_test.dart' show page, productJson;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';
import '../checkout/checkout_controller_test.dart' show waitUntil;

Product p(int id, {int price = 10000, int stock = 10, bool active = true}) =>
    ProductModel.fromJson(productJson(id: id, name: 'Produk $id', price: price, stock: stock)..['is_active'] = active);

void main() {
  late TestHarness h;
  late ProviderContainer c;

  Future<ProviderContainer> start({Map<String, dynamic>? user, int tenantId = 1, TestHarness? reuse}) async {
    h = reuse ?? TestHarness();
    if (reuse == null) await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(user ?? userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson(id: tenantId)]));
    final container = h.container();
    container.listen(sessionControllerProvider, (_, _) {});
    await waitUntil(container, () => container.read(sessionControllerProvider).status == SessionStatus.ready);
    container
      ..listen(cartControllerProvider, (_, _) {})
      ..listen(checkoutControllerProvider, (_, _) {})
      ..listen(heldCartsControllerProvider, (_, _) {});
    await container.read(heldCartsControllerProvider.future);
    return container;
  }

  HeldCartsController held() => c.read(heldCartsControllerProvider.notifier);
  CartController cart() => c.read(cartControllerProvider.notifier);

  tearDown(() => c.dispose());

  test('snapshot round-trip keeps prices and percentages exact', () {
    c = ProviderContainer();
    final product = ProductModel.fromJson(productJson(price: 12345.5));
    final again = ProductModel.fromJson(ProductModel.toJson(product));
    expect(again.price, Money.parse('12345.50'));
    expect(again.discountHundredths, 1250);
    expect(again.taxHundredths, 1100);
    expect(again.sku, product.sku);
    expect(again.barcode, product.barcode);
  });

  group('hold', () {
    setUp(() async => c = await start());

    test('parks cart + customer on the device, then clears them for the next customer', () async {
      cart().add(p(1), qty: 2);
      c.read(checkoutControllerProvider.notifier)
        ..setCustomer(const Customer(id: 7, name: 'Budi'))
        ..setPaymentMethod(PaymentMethod.cash);

      final parked = await held().hold();

      expect(parked.label, 'Budi');
      expect(parked.itemCount, 2);
      expect(c.read(cartControllerProvider).isEmpty, isTrue);
      expect(c.read(checkoutControllerProvider).customer, isNull);
      expect(c.read(checkoutControllerProvider).paymentMethod, isNull);
      expect(h.deviceStore.values.keys, contains('kagoem.held_carts.t1.u7'));
      expect(c.read(heldCartsControllerProvider).value, hasLength(1));
    });

    test('a note becomes the label; walk-in otherwise', () async {
      cart().add(p(1));
      expect((await held().hold(note: '  Meja 3 ')).label, 'Meja 3');
      cart().add(p(2));
      expect((await held().hold()).label, 'Walk-in');
      // Newest first.
      expect(c.read(heldCartsControllerProvider).value!.map((x) => x.label), ['Walk-in', 'Meja 3']);
    });

    test('empty cart cannot be held', () async {
      await expectLater(held().hold(), throwsA(isA<HoldException>()));
    });

    test('at most 20 holds', () async {
      for (var i = 0; i < 20; i++) {
        cart().add(p(1));
        await held().hold();
      }
      cart().add(p(1));
      await expectLater(held().hold(), throwsA(isA<HoldException>().having((e) => e.message, 'message', contains('Maksimal 20'))));
      expect(c.read(cartControllerProvider).isNotEmpty, isTrue, reason: 'cart kept when hold is refused');
    });
  });

  group('scope & persistence', () {
    test('survives an app restart, but is private per cashier and per tenant', () async {
      c = await start();
      cart().add(p(1));
      await held().hold(note: 'Meja 3');
      final store = h.deviceStore;
      c.dispose();

      // Same cashier, app restarted.
      final again = TestHarness(session: SessionStore(InMemoryKeyValueStore()));
      again.deviceStore.values.addAll(store.values);
      await again.session.saveToken('5|tok');
      c = await start(reuse: again);
      expect(c.read(heldCartsControllerProvider).value!.single.label, 'Meja 3');
      c.dispose();

      // Another cashier on the same device.
      final other = TestHarness(session: SessionStore(InMemoryKeyValueStore()));
      other.deviceStore.values.addAll(store.values);
      await other.session.saveToken('9|tok');
      c = await start(reuse: other, user: userJson(id: 99, name: 'Andi'));
      expect(c.read(heldCartsControllerProvider).value, isEmpty);
      c.dispose();

      // Same cashier, another tenant.
      final tenant2 = TestHarness(session: SessionStore(InMemoryKeyValueStore()));
      tenant2.deviceStore.values.addAll(store.values);
      await tenant2.session.saveToken('5|tok');
      c = await start(reuse: tenant2, tenantId: 2);
      expect(c.read(heldCartsControllerProvider).value, isEmpty);
    });
  });

  group('resume', () {
    setUp(() async => c = await start());

    void serverProducts(Map<int, Map<String, dynamic>?> products) {
      for (final e in products.entries) {
        h.backend.reply('GET', '/products/${e.key}', e.value == null ? 404 : 200, e.value == null ? {'message': 'x'} : ok(e.value));
      }
    }

    test('restores cart and customer with current server data and reports changes', () async {
      cart()
        ..add(p(1, price: 10000), qty: 2)
        ..add(p(2), qty: 1)
        ..add(p(3), qty: 5);
      c.read(checkoutControllerProvider.notifier).setCustomer(const Customer(id: 7, name: 'Budi'));
      final parked = await held().hold();

      serverProducts({
        1: productJson(id: 1, name: 'Produk 1', price: 12000, stock: 10), // price up
        2: null, // deleted
        3: productJson(id: 3, name: 'Produk 3', price: 10000, stock: 2), // stock now 2
      });
      final report = await held().resume(parked.id);

      final restored = c.read(cartControllerProvider);
      expect(restored.qtyOf(1), 2);
      expect(restored.lineFor(1)!.product.price, Money.rupiah(12000));
      expect(restored.qtyOf(2), 0);
      expect(restored.qtyOf(3), 2);
      expect(c.read(checkoutControllerProvider).customer?.name, 'Budi');
      expect(report.notes, [
        'Harga Produk 1 berubah: Rp 10.000 → Rp 12.000.',
        'Produk 2 tidak tersedia lagi.',
        'Stok Produk 3 tinggal 2.',
      ]);
      expect(c.read(heldCartsControllerProvider).value, isEmpty);
      expect(h.deviceStore.values.containsKey('kagoem.held_carts.t1.u7'), isFalse);
    });

    test('the cart in progress is held first, never lost', () async {
      cart().add(p(1));
      final first = await held().hold(note: 'Meja 1');
      cart().add(p(2), qty: 3);

      serverProducts({1: productJson(id: 1, name: 'Produk 1')});
      await held().resume(first.id);

      expect(c.read(cartControllerProvider).qtyOf(1), 1);
      final remaining = c.read(heldCartsControllerProvider).value!;
      expect(remaining.single.label, 'Keranjang sebelumnya');
      expect(remaining.single.lines.single.qty, 3);
    });

    test('offline: nothing changes, the hold is kept', () async {
      cart().add(p(1));
      final parked = await held().hold();
      cart().add(p(5));
      h.backend.failures['GET /products/1'] = DioExceptionType.connectionError;

      await expectLater(held().resume(parked.id), throwsA(isA<AppFailure>()));

      expect(c.read(cartControllerProvider).qtyOf(5), 1, reason: 'current cart untouched');
      expect(c.read(heldCartsControllerProvider).value!.single.id, parked.id);
    });
  });

  testWidgets('POS: TAHAN → badge → LANJUTKAN', (tester) async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
    h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
    h.backend.reply('GET', '/categories', 200, page([]));
    h.backend.reply('GET', '/products', 200, page([productJson(id: 1, name: 'Kopi', price: 10000, stock: 5)]));
    h.backend.reply('GET', '/products/1', 200, ok(productJson(id: 1, name: 'Kopi', price: 10000, stock: 5)));
    tester.view.physicalSize = const Size(1280, 800); // tablet: cart pane visible
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();
    c = ProviderScope.containerOf(tester.element(find.byType(KagoemPosApp)));

    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi'));
    await tester.tap(find.text('Kopi'));
    await tester.pump();
    expect(find.text('Keranjang (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cart-hold')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hold-note')), 'Meja 3');
    await tester.tap(find.byKey(const Key('hold-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi "Meja 3" ditahan.'), findsOneWidget);
    expect(find.textContaining('Keranjang masih kosong'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // badge

    await tester.tap(find.byKey(const Key('held-open')));
    await tester.pumpAndSettle();
    expect(find.text('Meja 3'), findsOneWidget);
    expect(find.text('Rp 19.425'), findsOneWidget); // 2 × 10.000 −12.5% +11%

    await tester.tap(find.text('LANJUTKAN'));
    await tester.pumpAndSettle();
    expect(find.text('Keranjang (2)'), findsOneWidget);
    expect(find.text('Transaksi "Meja 3" dilanjutkan.'), findsOneWidget);
    // Prevent tearDown from disposing the app's container.
    c = ProviderContainer();
  });
}

