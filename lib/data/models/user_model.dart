import '../../core/utils/json.dart';
import '../../domain/entities/user.dart';

/// Parses `UserResource` (backend/app/Http/Resources/UserResource.php).
abstract final class UserModel {
  static User fromJson(Map<String, dynamic> json) => User(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        email: Json.asString(json['email']),
        phone: Json.asStringOrNull(json['phone']),
        avatarUrl: Json.asStringOrNull(json['avatar_url']),
        isActive: Json.asBool(json['is_active'], fallback: true),
        branchId: Json.asIntOrNull(json['branch_id']),
        branchName: Json.asStringOrNull(json['branch_name']),
        roles: Json.asStringList(json['roles']),
        permissions: Json.asStringList(json['permissions']),
      );
}
