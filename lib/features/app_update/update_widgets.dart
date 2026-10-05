import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/widgets/feedback.dart';
import 'app_update.dart';

/// Opens the APK link outside the app: the browser downloads it and the
/// cashier taps the download to install. Overridable in tests.
final openDownloadProvider = Provider<Future<bool> Function(Uri url)>((ref) {
  return (url) => launchUrl(url, mode: LaunchMode.externalApplication);
});

Future<void> _startDownload(BuildContext context, WidgetRef ref, AppRelease release) async {
  bool opened;
  try {
    opened = await ref.read(openDownloadProvider)(release.downloadUrl);
  } catch (_) {
    opened = false;
  }
  if (!context.mounted) return;
  showQuickMessage(
    context,
    opened
        ? 'Mengunduh versi ${release.version}. Buka file yang terunduh untuk memasang.'
        : 'Tidak dapat membuka tautan unduhan.',
    isError: !opened,
  );
}

/// "Update tersedia" card on the dashboard. Shows nothing when the app is
/// up to date, the check failed, or the user postponed this version.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(updateToShowProvider);
    if (release == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('update-banner'),
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Update tersedia: versi ${release.version}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 4, 8, 0),
                child: Text(
                  'Versi terpasang ${ref.watch(currentAppVersionProvider)}'
                  '${release.sizeLabel == null ? '' : ' · unduhan ${release.sizeLabel}'}.',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('update-later'),
                    onPressed: () => ref.read(dismissedUpdateProvider.notifier).dismiss(release.version),
                    child: const Text('Nanti'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('update-now'),
                    onPressed: () => _startDownload(context, ref, release),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.download),
                    label: const Text('Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tentang Aplikasi": installed version and a manual update check.
Future<void> showAboutApp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _AboutDialog(),
    );

class _AboutDialog extends ConsumerWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final check = ref.watch(availableUpdateProvider);
    final version = ref.watch(currentAppVersionProvider);

    final status = check.when(
      loading: () => const Text('Memeriksa pembaruan...'),
      error: (_, _) => const Text('Pembaruan tidak dapat diperiksa.'),
      data: (release) => release == null
          ? const Text('Aplikasi sudah versi terbaru.')
          : Text('Versi ${release.version} tersedia.', style: const TextStyle(fontWeight: FontWeight.w700)),
    );

    return AlertDialog(
      title: Text(config.appName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versi ${version.isEmpty ? '-' : version}'),
          Text(config.apiBaseUrl, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          status,
        ],
      ),
      actions: [
        TextButton(
          key: const Key('update-recheck'),
          onPressed: () => ref.invalidate(availableUpdateProvider),
          child: const Text('Periksa lagi'),
        ),
        if (check.value != null)
          FilledButton(
            onPressed: () {
              final release = check.value!;
              Navigator.pop(context);
              _startDownload(context, ref, release);
            },
            child: const Text('Update'),
          )
        else
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
      ],
    );
  }
}
