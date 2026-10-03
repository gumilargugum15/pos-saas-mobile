import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../outlet/outlet_controller.dart';
import '../../outlet/outlet_picker.dart';
import '../../settings/settings_providers.dart';
import '../../tenant/presentation/switch_tenant.dart';
import '../application/dashboard_providers.dart';

/// Cashier dashboard: who/where, the big "start transaction" button, a few
/// tenant-wide figures and the quick menu. Deliberately simple.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const posRoute = '/pos';
  static const productsRoute = '/products';

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
              'printer' => context.push('/printer'),
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
                value: 'printer',
                child: ListTile(leading: Icon(Icons.print), title: Text('Printer Struk')),
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
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
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
                          const _OutletRow(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('start-transaction'),
                    onPressed: () => context.push(posRoute),
                    icon: const Icon(Icons.point_of_sale, size: 28),
                    label: const Text('MULAI TRANSAKSI'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(72),
                      textStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _StatsSection(),
                  const SizedBox(height: 24),
                  Text('Menu', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.2,
                    children: [
                      _MenuTile(icon: Icons.point_of_sale, label: 'POS', onTap: () => context.push(posRoute)),
                      _MenuTile(
                        icon: Icons.receipt_long,
                        label: 'Transaksi',
                        onTap: () => context.push('/transactions'),
                      ),
                      _MenuTile(
                        icon: Icons.people_outline,
                        label: 'Pelanggan',
                        onTap: () => context.push('/customers'),
                      ),
                      _MenuTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Produk',
                        onTap: () => context.push(productsRoute),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(dashboardSummaryProvider);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hari ini · seluruh toko', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        summary.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off),
              title: const Text('Ringkasan belum bisa dimuat.'),
              subtitle: Text(error is AppFailure ? error.message : 'Terjadi kesalahan.'),
              trailing: TextButton(
                onPressed: () => ref.invalidate(dashboardSummaryProvider),
                child: const Text('Coba lagi'),
              ),
            ),
          ),
          data: (s) => Column(
            children: [
              _StatCard(label: 'Penjualan', value: ref.money(s.todaySales), icon: Icons.payments_outlined),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(label: 'Transaksi', value: '${s.transactionsCount}', icon: Icons.receipt_long),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(label: 'Produk aktif', value: '${s.productsCount}', icon: Icons.inventory_2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: textTheme.bodyMedium),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
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

class _OutletRow extends ConsumerWidget {
  const _OutletRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlet = ref.watch(outletControllerProvider);
    final value = outlet.when(
      loading: () => 'Memuat...',
      error: (_, _) => 'Gagal dimuat',
      data: (o) => o.selected?.name ?? (o.options.isEmpty ? 'Tanpa outlet' : 'Belum dipilih'),
    );
    final state = outlet.value;
    final canPick = state != null && (state.canChange || state.needsSelection);

    return Row(
      children: [
        Expanded(child: _InfoRow(label: 'Outlet', value: value)),
        if (canPick)
          TextButton(
            key: const Key('dashboard-outlet'),
            onPressed: () => showOutletPicker(context, ref, state),
            child: Text(state.selected == null ? 'Pilih' : 'Ganti'),
          ),
      ],
    );
  }
}
