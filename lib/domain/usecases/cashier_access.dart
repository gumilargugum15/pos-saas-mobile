import '../entities/tenant.dart';
import '../entities/user.dart';

/// Permission names from the backend `RoleAndPermissionSeeder`.
abstract final class Permissions {
  static const manageSales = 'manage-sales';
  static const manageCustomers = 'manage-customers';
  static const operateCashDrawer = 'operate-cash-drawer';
  static const manageProducts = 'manage-products';
}

/// Plan module keys from the backend `config/plans.php`.
abstract final class PlanModules {
  static const sales = 'sales';
  static const products = 'products';
}

enum AccessDenialReason {
  /// The user has no active tenant membership at all.
  noTenant,

  /// The user lacks `manage-sales`, which `POST /sales` requires.
  missingPermission,

  /// The tenant's plan does not include the `sales` module.
  moduleUnavailable,
}

/// Decides whether the cashier app may be used, with the same rule the web
/// POS applies to its `/pos` page: permission `manage-sales` + module
/// `sales`. Role names are never checked: roles are editable in the backend.
/// (docs/CASHIER_PERMISSION.md §2)
abstract final class CashierAccess {
  static AccessDenialReason? evaluate(User user, Tenant tenant) {
    if (!user.can(Permissions.manageSales)) return AccessDenialReason.missingPermission;
    if (!tenant.hasModule(PlanModules.sales)) return AccessDenialReason.moduleUnavailable;
    return null;
  }
}

/// Feature toggles inside the app. These only shape the UI; the backend
/// still authorizes every request (docs/CASHIER_PERMISSION.md §6).
class CashierCapabilities {
  const CashierCapabilities(this.user, {this.tenant});

  final User user;
  final Tenant? tenant;

  bool get canCheckout => user.can(Permissions.manageSales);
  bool get canCreateCustomer => user.can(Permissions.manageCustomers);
  bool get canUseCashDrawer => user.can(Permissions.operateCashDrawer);

  /// Edit products (Admin / Owner): same gate as `PUT /products/{id}` —
  /// `can:manage-products` + plan module `products`.
  bool get canEditProducts =>
      user.can(Permissions.manageProducts) && (tenant?.hasModule(PlanModules.products) ?? true);

  /// Allowed by the backend for Kasir, but not part of the mobile MVP (D2).
  bool get canRefund => false;
}
