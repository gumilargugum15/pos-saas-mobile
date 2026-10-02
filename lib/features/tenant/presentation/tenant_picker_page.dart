import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../../domain/entities/tenant.dart';
import '../../auth/application/session_controller.dart';

class TenantPickerPage extends ConsumerStatefulWidget {
  const TenantPickerPage({super.key});

  @override
  ConsumerState<TenantPickerPage> createState() => _TenantPickerPageState();
}

class _TenantPickerPageState extends ConsumerState<TenantPickerPage> {
  int? _selectingId;

  Future<void> _select(Tenant tenant) async {
    if (_selectingId != null) return;
    setState(() => _selectingId = tenant.id);
    try {
      await ref.read(sessionControllerProvider.notifier).selectTenant(tenant);
    } finally {
      if (mounted) setState(() => _selectingId = null);
    }
  }

  Future<void> _logout() async {
    if (await confirmLogout(context)) {
      await ref.read(sessionControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final current = session.activeTenant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Perusahaan'),
        // Back = keep the tenant that was active before switching.
        leading: current == null
            ? null
            : IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _select(current),
              ),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Keluar')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (session.message != null) ...[
                  MessageBanner(session.message!, tone: BannerTone.info),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Halo, ${session.user?.name ?? ''}. Pilih perusahaan (tenant) untuk sesi kasir ini.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                for (final tenant in session.tenants) ...[
                  _TenantTile(
                    tenant: tenant,
                    isCurrent: tenant.id == current?.id,
                    busy: _selectingId == tenant.id,
                    onTap: _selectingId == null ? () => _select(tenant) : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TenantTile extends StatelessWidget {
  const _TenantTile({required this.tenant, required this.isCurrent, required this.busy, this.onTap});

  final Tenant tenant;
  final bool isCurrent;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final details = [tenant.role, if (tenant.plan != null) 'Paket ${tenant.plan}'].whereType<String>().join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(child: Text(tenant.name.isEmpty ? '?' : tenant.name[0].toUpperCase())),
        title: Text(tenant.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Icon(isCurrent ? Icons.check_circle : Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
