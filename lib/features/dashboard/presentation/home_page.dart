import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../tenant/presentation/switch_tenant.dart';

/// Phase 2 home: shows who is logged in and where. The sales dashboard,
/// catalog and POS screens replace the placeholder body in Phase 3.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (await confirmLogout(context)) {
      await ref.read(sessionControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final tenant = session.activeTenant;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KAGOEM POS'),
        actions: [
          const EnvironmentBadge(),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) => switch (value) {
              'switch' => switchTenantOrNotify(context, ref),
              'logout' => _logout(context, ref),
              _ => null,
            },
            itemBuilder: (context) => [
              if (session.canSwitchTenant)
                const PopupMenuItem(
                  value: 'switch',
                  child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('Ganti Perusahaan')),
                ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Keluar')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(label: 'Kasir', value: user?.name ?? '-'),
                        _InfoRow(label: 'Perusahaan', value: tenant?.name ?? '-'),
                        _InfoRow(label: 'Outlet', value: user?.branchName ?? 'Belum ditentukan'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('MULAI TRANSAKSI'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Katalog, keranjang, dan transaksi tersedia pada tahap berikutnya.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: textTheme.bodyMedium)),
          Expanded(child: Text(value, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
