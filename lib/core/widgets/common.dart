import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// App logo + name, used on the splash and login screens.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          child: Icon(Icons.point_of_sale_rounded, color: scheme.onPrimary, size: size * 0.55),
        ),
        const SizedBox(height: 16),
        Text(
          'KAGOEM POS',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
        ),
        const SizedBox(height: 4),
        Text('Aplikasi Kasir', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

enum BannerTone { error, info }

class MessageBanner extends StatelessWidget {
  const MessageBanner(this.message, {super.key, this.tone = BannerTone.error});

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = tone == BannerTone.error;
    final background = isError ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground = isError ? scheme.onErrorContainer : scheme.onSecondaryContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline : Icons.info_outline, color: foreground),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: TextStyle(color: foreground))),
          ],
        ),
      ),
    );
  }
}

/// Visible on non-production builds so test devices are never mistaken for
/// live tills.
class EnvironmentBadge extends ConsumerWidget {
  const EnvironmentBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    if (config.isProduction) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(config.environment.name.toUpperCase()),
      backgroundColor: scheme.tertiaryContainer,
      labelStyle: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w700),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Centers content and caps its width on tablets.
class CenteredPane extends StatelessWidget {
  const CenteredPane({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

Future<bool> confirmLogout(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keluar dari aplikasi?'),
      content: const Text('Anda perlu login kembali untuk melakukan transaksi.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Keluar')),
      ],
    ),
  );
  return result ?? false;
}
