import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepositoryImpl(
    TenantRemoteDataSource(ref.watch(apiClientProvider)),
    ref.watch(sessionStoreProvider),
  );
});
