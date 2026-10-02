import '../../core/utils/json.dart';
import '../../domain/entities/tenant.dart';

/// Parses `TenantMembershipResource`
/// (backend/app/Http/Resources/TenantMembershipResource.php).
abstract final class TenantModel {
  static Tenant fromJson(Map<String, dynamic> json) => Tenant(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        slug: Json.asString(json['slug']),
        role: Json.asStringOrNull(json['role']),
        plan: Json.asStringOrNull(json['plan']),
        modules: Json.asStringListOrNull(json['modules']),
      );
}
