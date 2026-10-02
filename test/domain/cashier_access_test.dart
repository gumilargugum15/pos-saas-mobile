import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/domain/entities/tenant.dart';
import 'package:kagoem_pos_mobile/domain/entities/user.dart';
import 'package:kagoem_pos_mobile/domain/usecases/cashier_access.dart';

User user(List<String> permissions, {List<String> roles = const []}) =>
    User(id: 1, name: 'A', email: 'a@b.c', permissions: permissions, roles: roles);

void main() {
  const allModules = Tenant(id: 1, name: 'T');
  const starterNoSales = Tenant(id: 2, name: 'T2', modules: ['products', 'reports']);

  test('Kasir (manage-sales) is allowed', () {
    expect(CashierAccess.evaluate(user(['manage-sales', 'operate-cash-drawer'], roles: ['Kasir']), allModules), isNull);
  });

  test('Owner/Admin with manage-sales is allowed (web POS parity)', () {
    expect(CashierAccess.evaluate(user(['manage-sales', 'manage-users'], roles: ['Owner']), allModules), isNull);
  });

  test('a role named Kasir without the permission is denied: names are not trusted', () {
    expect(
      CashierAccess.evaluate(user(['operate-cash-drawer'], roles: ['Kasir']), allModules),
      AccessDenialReason.missingPermission,
    );
  });

  test('warehouse user (admin-only features, no sales) is denied', () {
    expect(CashierAccess.evaluate(user(['manage-inventory'], roles: ['Gudang']), allModules),
        AccessDenialReason.missingPermission);
  });

  test('plan without the sales module is denied', () {
    expect(CashierAccess.evaluate(user(['manage-sales']), starterNoSales), AccessDenialReason.moduleUnavailable);
  });

  test('capabilities follow permissions; refund stays off in the MVP', () {
    final kasir = CashierCapabilities(user(['manage-sales', 'operate-cash-drawer']));
    expect(kasir.canCheckout, isTrue);
    expect(kasir.canUseCashDrawer, isTrue);
    expect(kasir.canCreateCustomer, isFalse);
    expect(kasir.canRefund, isFalse);

    final owner = CashierCapabilities(user(['manage-sales', 'manage-customers']));
    expect(owner.canCreateCustomer, isTrue);
  });
}
