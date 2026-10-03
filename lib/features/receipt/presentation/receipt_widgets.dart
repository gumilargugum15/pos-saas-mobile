import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/printing/printer_service.dart';
import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/sale.dart';
import '../../transactions/application/transactions_controller.dart';
import '../receipt_formatter.dart';
import '../receipt_providers.dart';

const printerRoute = '/printer';

/// What the paper will look like (monospace, real column width).
class ReceiptPreview extends ConsumerWidget {
  const ReceiptPreview({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(receiptActionsProvider);
    final lines = actions.lines(sale);
    final formatter = actions.formatter;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Text(
                  line.align == LineAlign.center ? formatter.centerText(line.text) : line.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.3,
                    color: Colors.black,
                    fontWeight: line.bold ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Print / share buttons with their own busy state (no double printing)
/// and cashier-friendly errors. A missing printer never crashes the flow.
class ReceiptActionButtons extends ConsumerStatefulWidget {
  const ReceiptActionButtons({super.key, required this.sale});

  final Sale sale;

  @override
  ConsumerState<ReceiptActionButtons> createState() => _ReceiptActionButtonsState();
}

class _ReceiptActionButtonsState extends ConsumerState<ReceiptActionButtons> {
  bool _printing = false;

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    var needsSetup = false;
    try {
      await ref.read(receiptActionsProvider).print(widget.sale);
      if (mounted) showQuickMessage(context, 'Struk dicetak.');
    } on PrinterNotConfigured {
      needsSetup = true;
    } on PrinterException catch (e) {
      if (mounted) showQuickMessage(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showQuickMessage(context, 'Gagal mencetak struk.', isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
    // Not "printing" while the cashier reads the setup prompt.
    if (needsSetup && mounted) await _askToSetUpPrinter();
  }

  Future<void> _askToSetUpPrinter() async {
    final setUp = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Printer belum diatur'),
        content: const Text('Pilih printer Bluetooth yang sudah dipasangkan di perangkat ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nanti')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Atur Printer')),
        ],
      ),
    );
    if ((setUp ?? false) && mounted) await context.push(printerRoute);
  }

  Future<void> _share() async {
    try {
      await ref.read(receiptActionsProvider).share(widget.sale);
    } catch (e) {
      if (mounted) showQuickMessage(context, 'Struk tidak dapat dibagikan.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('receipt-print'),
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print),
            label: Text(_printing ? 'Mencetak...' : 'CETAK'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('receipt-share'),
            onPressed: _share,
            icon: const Icon(Icons.share),
            label: const Text('BAGIKAN'),
          ),
        ),
      ],
    );
  }
}

/// Receipt preview + reprint/share for a past sale.
class ReceiptPage extends ConsumerWidget {
  const ReceiptPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleDetailProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Struk')),
      body: SafeArea(
        child: sale.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StatusView(
            icon: Icons.cloud_off,
            message: e is AppFailure ? e.message : 'Gagal memuat transaksi.',
            actionLabel: 'Coba Lagi',
            onAction: () => ref.invalidate(saleDetailProvider(saleId)),
          ),
          data: (sale) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ReceiptPreview(sale: sale),
              const SizedBox(height: 16),
              ReceiptActionButtons(sale: sale),
            ],
          ),
        ),
      ),
    );
  }
}
