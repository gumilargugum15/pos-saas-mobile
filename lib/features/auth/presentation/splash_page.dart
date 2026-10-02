import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../application/session_controller.dart';

class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final failed = session.status == SessionStatus.startupError;

    return Scaffold(
      body: SafeArea(
        child: CenteredPane(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: 40),
              if (!failed) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Memeriksa sesi...'),
              ] else ...[
                MessageBanner(session.message ?? 'Gagal memuat sesi.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: controller.restore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: controller.logout,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('Keluar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
