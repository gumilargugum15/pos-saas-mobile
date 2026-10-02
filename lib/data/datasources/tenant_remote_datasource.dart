import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/tenant.dart';
import '../models/tenant_model.dart';

class TenantRemoteDataSource {
  const TenantRemoteDataSource(this._api);

  final ApiClient _api;

  /// `GET /tenants` (not paginated).
  Future<List<Tenant>> tenants() async {
    final response = await _api.get(
      '/tenants',
      parse: (data) => [for (final t in data as List) TenantModel.fromJson(Json.asMap(t))],
    );
    return response.data;
  }
}
