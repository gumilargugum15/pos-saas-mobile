import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/printing/printer_service.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../settings/settings_providers.dart';
import '../receipt_formatter.dart';
import '../receipt_providers.dart';

final _devicesProvider = FutureProvider.autoDispose<List<PrinterDevice>>((ref) {
  return ref.watch(printerServiceProvider).devices();
});

/// Choose the Bluetooth printer, paper width, and print a test page.
class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  ConsumerState<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends ConsumerState<PrinterSettingsPage> {
  bool _testing = false;

  Future<void> _testPrint() async {
    setState(() => _testing = true);
    try {
      await ref.read(receiptActionsProvider).printTest();
      if (mounted) showQuickMessage(context, 'Test print terkirim.');
    } on PrinterNotConfigured {
      if (mounted) showQuickMessage(context, 'Pilih printer terlebih dahulu.', isError: true);
    } on PrinterException catch (e) {
      if (mounted) showQuickMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(printerSettingsProvider).value ?? const PrinterSettings();
    final devices = ref.watch(_devicesProvider);
    final controller = ref.read(printerSettingsProvider.notifier);
    final storePaper = PaperSize.fromSetting(ref.watch(settingsProvider).value?['receipt_paper_size']);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Struk')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(_devicesProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const MessageBanner(
                    'Pasangkan (pair) printer thermal di Pengaturan Bluetooth Android terlebih dahulu, '
                    'lalu pilih di bawah ini.',
                    tone: BannerTone.info,
                  ),
                  const SizedBox(height: 16),
                  Text('Printer Bluetooth', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  devices.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth_disabled),
                        title: Text(e is PrinterException ? e.message : 'Daftar printer tidak dapat dimuat.'),
                        trailing: TextButton(
                          onPressed: () => ref.invalidate(_devicesProvider),
                          child: const Text('Coba lagi'),
                        ),
                      ),
                    ),
                    data: (list) => list.isEmpty
                        ? const Card(
                            child: ListTile(
                              leading: Icon(Icons.print_disabled),
                              title: Text('Belum ada perangkat Bluetooth yang dipasangkan.'),
                            ),
                          )
                        : Card(
                            child: Column(
                              children: [
                                for (final d in list)
                                  ListTile(
                                    leading: Icon(
                                      d == settings.device ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: d == settings.device ? Theme.of(context).colorScheme.primary : null,
                                    ),
                                    title: Text(d.name),
                                    subtitle: Text(d.address),
                                    onTap: () => controller.setDevice(d),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (settings.device != null)
                    TextButton(
                      onPressed: () => controller.setDevice(null),
                      child: Text('Lupakan printer ${settings.device!.name}'),
                    ),
                  const SizedBox(height: 16),
                  Text('Lebar Kertas', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<PaperSize?>(
                    segments: [
                      ButtonSegment(value: null, label: Text('Ikuti toko (${storePaper.label})')),
                      for (final p in PaperSize.values) ButtonSegment(value: p, label: Text(p.label)),
                    ],
                    selected: {settings.paperOverride},
                    onSelectionChanged: (s) => controller.setPaper(s.first),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: settings.device == null || _testing ? null : _testPrint,
                    icon: const Icon(Icons.receipt),
                    label: Text(_testing ? 'Mencetak...' : 'TEST PRINT'),
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
