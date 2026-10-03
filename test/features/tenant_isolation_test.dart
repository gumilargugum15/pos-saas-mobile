import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/domain/entities/party.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/cart_controller.dart';
import 'package:kagoem_pos_mobile/features/checkout/application/checkout_controller.dart';
import 'package:kagoem_pos_mobile/features/products/application/catalog_controller.dart';

import '../data/catalog_repository_test.dart' show page, productJson;
import '../helpers/fake_backend.dart';
import '../helpers/test_app.dart';
import 'checkout/checkout_controller_test.dart' show kopi, waitUntil;

/// "Jangan pernah mencampur data antar tenant": switching tenant must reset
/// everything tenant-scoped on the device and re-scope every request.
void main() {
  late TestHarness h;
  late ProviderContainer c;

  setUp(() async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    await h.session.saveTenantId(1);
    await h.session.saveBranchId(3);
    h.backend.reply('GET', '/auth/me', 200, ok(userJson(branchId: null)));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson(id: 1, name: 'Toko ABC'), tenantJson(id: 2, name: 'Toko XYZ')]));
    h.backend.reply('GET', '/categories', 200, page([]));
    h.backend.on('GET', '/products', (r) {
      final tenant = r.headers['X-Tenant-ID'];
      return (status: 200, body: page([productJson(id: tenant == '1' ? 1 : 2, name: 'Produk tenant $tenant')]));
    });

    c = h.container();
    c.listen(sessionControllerProvider, (_, _) {});
    await waitUntil(c, () => c.read(sessionControllerProvider).status == SessionStatus.ready);
    for (final p in [cartControllerProvider, checkoutControllerProvider, catalogControllerProvider]) {
      c.listen(p, (_, _) {});
    }
  });

  tearDown(() => c.dispose());

  test('switching tenant clears cart, checkout and catalog; requests use the new tenant', () async {
    await waitUntil(c, () => c.read(catalogControllerProvider).items.isNotEmpty);
    expect(c.read(catalogControllerProvider).items.single.name, 'Produk tenant 1');

    c.read(cartControllerProvider.notifier).add(kopi);
    c.read(checkoutControllerProvider.notifier)
      ..setCustomer(const Customer(id: 7, name: 'Budi'))
      ..setPaymentMethod(PaymentMethod.cash);

    final session = c.read(sessionControllerProvider.notifier);
    await session.switchTenant();
    final xyz = c.read(sessionControllerProvider).tenants.firstWhere((t) => t.id == 2);
    await session.selectTenant(xyz);

    expect(c.read(activeTenantProvider)?.id, 2);
    expect(c.read(cartControllerProvider).isEmpty, isTrue);
    expect(c.read(checkoutControllerProvider).customer, isNull);
    expect(c.read(checkoutControllerProvider).paymentMethod, isNull);
    // The outlet chosen for tenant 1 is not carried over.
    expect(h.session.branchId, isNull);

    await waitUntil(c, () => c.read(catalogControllerProvider).items.firstOrNull?.name == 'Produk tenant 2');
    final last = h.backend.calls('GET', '/products').last;
    expect(last.headers['X-Tenant-ID'], '2');
  });

  test('logout clears the cart as well', () async {
    h.backend.reply('POST', '/auth/logout', 200, ok(null));
    c.read(cartControllerProvider.notifier).add(kopi);

    await c.read(sessionControllerProvider.notifier).logout();

    expect(c.read(cartControllerProvider).isEmpty, isTrue);
    expect(h.store.values, isEmpty);
  });
}
