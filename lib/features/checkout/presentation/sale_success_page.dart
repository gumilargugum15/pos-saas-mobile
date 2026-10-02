import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/sale.dart';
import '../../settings/settings_providers.dart';
import '../application/checkout_controller.dart';

/// "TRANSAKSI BERHASIL" with the server's numbers. Printing and sharing
/// are added with the receipt module (Phase 5).
class SaleSuccessPage extends ConsumerWidget {
  const SaleSuccessPage({super.key});

  void _newTransaction(BuildContext context, WidgetRef ref) {
    ref.read(checkoutControllerProvider.notifier).startNew();
    context.go('/pos');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutControllerProvider);
    final sale = state.sale;
    if (sale == null) {
      // E.g. restored after the app was killed: nothing to show.
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton(onPressed: () => _newTransaction(context, ref), child: const Text('TRANSAKSI BARU')),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _newTransaction(context, ref);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.check_circle, color: BrandColors.success, size: 88),
                  const SizedBox(height: 12),
                  Text(
                    'TRANSAKSI BERHASIL',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  if (state.replayed)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Transaksi ini sudah tersimpan sebelumnya.', textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 24),
                  SaleSummaryCard(sale: sale),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('new-transaction'),
                    autofocus: true,
                    onPressed: () => _newTransaction(context, ref),
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('TRANSAKSI BARU'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.push('/transactions/${sale.id}'),
                    child: const Text('Lihat Detail'),
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

/// Invoice, total, payment, received and change.
class SaleSummaryCard extends ConsumerWidget {
  const SaleSummaryCard({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(label, style: textTheme.bodyLarge),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: big
                        ? textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)
                        : textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row('Invoice', sale.invoiceNumber),
            row('Total', ref.money(sale.grandTotal), big: true),
            const Divider(),
            row('Pembayaran', sale.paymentLabel),
            row('Diterima', ref.money(sale.paid)),
            row('Kembalian', ref.money(sale.change), big: sale.change.minor > 0),
          ],
        ),
      ),
    );
  }
}
