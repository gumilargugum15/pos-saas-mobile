/// A tenant the user is an active member of (`TenantMembershipResource`).
class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    this.slug = '',
    this.role,
    this.plan,
    this.modules,
  });

  /// Sent as the `X-Tenant-ID` header.
  final int id;
  final String name;
  final String slug;

  /// Membership role label (`tenant_users.role`). Display only.
  final String? role;
  final String? plan;

  /// Plan modules (`products`, `sales`, `reports`, `inventory`).
  /// `null` means every module is available.
  final List<String>? modules;

  bool hasModule(String module) => modules == null || modules!.contains(module);

  @override
  bool operator ==(Object other) => other is Tenant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
