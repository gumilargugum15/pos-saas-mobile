import '../entities/tenant.dart';

abstract interface class TenantRepository {
  /// Active memberships of active tenants (`GET /tenants`).
  Future<List<Tenant>> fetchTenants();

  /// The tenant chosen on this device, if any. The backend keeps no server
  /// side "active tenant": the client sends it on every request.
  int? get selectedTenantId;

  Future<void> select(int tenantId);

  Future<void> clearSelection();
}
