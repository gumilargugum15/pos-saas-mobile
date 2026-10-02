import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../tenant/presentation/switch_tenant.dart';
import '../../../domain/usecases/cashier_access.dart';
import '../application/session_controller.dart';

class AccessDeniedPage extends ConsumerWidget {
  const AccessDeniedPage({super.key});

  static String reasonText(AccessDenialReason? reason, String? tenantName) => switch (reason) {
        AccessDenialReason.noTenant =>
          'Akun Anda belum terdaftar aktif di perusahaan (tenant) mana pun. Hubungi pemilik toko.',
        AccessDenialReason.missingPermission =>
          'Akun ini tidak memiliki izin kasir. Hubungi administrator toko untuk mendapatkan akses penjualan.',
        AccessDenialReason.moduleUnavailable =>
          'Paket langganan ${tenantName ?? 'perusahaan ini'} tidak mencakup fitur Penjualan. '
              'Hubungi pemilik toko untuk upgrade paket.',
        null => 'Anda tidak memiliki akses ke aplikasi kasir.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: CenteredPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.block, size: 72, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'Akses Ditolak',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                reasonText(session.denialReason, session.activeTenant?.name),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (session.user != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Login sebagai ${session.user!.email}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 32),
              if (session.canSwitchTenant) ...[
                FilledButton.icon(
                  onPressed: () => switchTenantOrNotify(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Ganti Perusahaan'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: controller.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
