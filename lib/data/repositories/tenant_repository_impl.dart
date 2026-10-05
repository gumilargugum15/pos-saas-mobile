import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../../domain/entities/tenant.dart';
import '../../domain/repositories/tenant_repository.dart';
import '../datasources/tenant_remote_datasource.dart';

class TenantRepositoryImpl implements TenantRepository {
  TenantRepositoryImpl(this._remote, this._session);

  final TenantRemoteDataSource _remote;
  final SessionStore _session;

  @override
  Future<List<Tenant>> fetchTenants() => _remote.tenants();

  @override
  int? get selectedTenantId => _session.tenantId;

  @override
  Future<void> select(int tenantId) => _session.saveTenantId(tenantId);

  @override
  Future<void> clearSelection() => _session.saveTenantId(null);
}

/// pos-cashier backends have a single store and no `/tenants` endpoint:
/// the store itself is the only "tenant". Nothing is persisted and no
/// `X-Tenant-ID` header is ever sent (the session never stores a tenant).
class SingleStoreTenantRepository implements TenantRepository {
  SingleStoreTenantRepository(String storeName)
      : _store = Tenant(id: storeTenantId, name: storeName, slug: 'store');

  /// Stable local id, used to scope device data (e.g. held carts).
  static const storeTenantId = 0;

  final Tenant _store;

  @override
  Future<List<Tenant>> fetchTenants() async => [_store];

  @override
  int? get selectedTenantId => storeTenantId;

  @override
  Future<void> select(int tenantId) async {}

  @override
  Future<void> clearSelection() async {}
}

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.multiTenant) return SingleStoreTenantRepository(config.appName);
  return TenantRepositoryImpl(
    TenantRemoteDataSource(ref.watch(apiClientProvider)),
    ref.watch(sessionStoreProvider),
  );
});
