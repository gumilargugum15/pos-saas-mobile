/// The authenticated user, as returned by `UserResource`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.isActive = true,
    this.branchId,
    this.branchName,
    this.roles = const [],
    this.permissions = const [],
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final bool isActive;

  /// Home branch. When set, the backend forces it on every branch-aware call.
  final int? branchId;
  final String? branchName;

  /// Spatie role names (global, not per tenant). Display only.
  final List<String> roles;

  /// Spatie permission names. All access decisions use these.
  final List<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  String? get primaryRole => roles.firstOrNull;
}
