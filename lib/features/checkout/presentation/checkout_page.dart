import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/rupiah_input.dart';
import '../../../domain/entities/cart.dart';
import '../../../domain/entities/party.dart';
import '../../../domain/entities/sale.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/presentation/cart_widgets.dart';
import '../../customers/presentation/customer_widgets.dart';
import '../../outlet/outlet_controller.dart';
import '../../outlet/outlet_picker.dart';
import '../../settings/settings_providers.dart';
import '../application/checkout_controller.dart';

/// Customer → outlet → payment → pay, on one screen.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  static const successRoute = '/pos/success';

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _cash = TextEditingController();

  @override
  void initState() {
    super.initState();
    final received = ref.read(checkoutControllerProvider).cashReceived;
    if (received != null) _cash.text = formatRupiahDigits('$received');
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  void _setCash(int rupiah) {
    _cash.text = formatRupiahDigits('$rupiah');
    ref.read(checkoutControllerProvider.notifier).setCashReceived(rupiah);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(checkoutControllerProvider.select((s) => s.phase), (_, phase) {
      if (phase == CheckoutPhase.success) context.go(CheckoutPage.successRoute);
    });

    final state = ref.watch(checkoutControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    final outlet = ref.watch(outletControllerProvider);
    final controller = ref.read(checkoutControllerProvider.notifier);

    if (state.phase == CheckoutPhase.unknown) {
      return const _UnknownOutcomeScaffold();
    }
    if (cart.isEmpty && state.phase != CheckoutPhase.success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pembayaran')),
        body: const Center(child: Text('Keranjang kosong.')),
      );
    }

    final reason = controller.blockingReason(cart, outlet.value);
    final busy = state.isSubmitting;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Pembayaran'), automaticallyImplyLeading: !busy),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TotalCard(cart: cart),
                  const SizedBox(height: 16),
                  _OutletTile(outlet: outlet, enabled: !busy),
                  _CustomerTile(customer: state.customer, enabled: !busy),
                  const SizedBox(height: 16),
                  Text('Metode Pembayaran', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in PaymentMethod.values)
                        ChoiceChip(
                          key: Key('pay-${method.apiValue}'),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(method.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                          selected: state.paymentMethod == method,
                          onSelected: busy ? null : (_) => controller.setPaymentMethod(method),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.paymentMethod?.isCash ?? false)
                    _CashSection(cash: _cash, cart: cart, enabled: !busy, onQuick: _setCash)
                  else if (state.paymentMethod != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text('Dibayar ${ref.money(Money.rupiah(cart.grandTotal.rupiahCeil))}'),
                        subtitle: Text('Pastikan pembayaran ${state.paymentMethod!.label} sudah diterima.'),
                      ),
                    ),
                  if (state.failure != null) ...[
                    const SizedBox(height: 16),
                    MessageBanner(state.failure!.message),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reason != null && !busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(reason, textAlign: TextAlign.center),
                  ),
                FilledButton(
                  key: const Key('checkout-pay'),
                  onPressed: busy || reason != null ? null : controller.submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                  child: busy
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                            SizedBox(width: 12),
                            Text('Memproses transaksi...'),
                          ],
                        )
                      : Text('BAYAR ${ref.money(Money.rupiah(cart.grandTotal.rupiahCeil))}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends ConsumerWidget {
  const _TotalCard({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(child: Text('${cart.itemCount} item', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Ubah')),
              ],
            ),
          ),
          CartTotals(cart: cart),
        ],
      ),
    );
  }
}

class _OutletTile extends ConsumerWidget {
  const _OutletTile({required this.outlet, required this.enabled});

  final AsyncValue<OutletState> outlet;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return outlet.when(
      loading: () => const ListTile(leading: Icon(Icons.store), title: Text('Memuat outlet...')),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.store),
        title: const Text('Outlet gagal dimuat'),
        subtitle: Text(e is AppFailure ? e.message : ''),
        trailing: TextButton(onPressed: () => ref.invalidate(outletControllerProvider), child: const Text('Coba lagi')),
      ),
      data: (o) {
        if (o.isFixed || o.options.isEmpty) {
          return ListTile(
            leading: const Icon(Icons.store),
            title: Text(o.selected?.name ?? 'Tanpa outlet'),
            subtitle: const Text('Outlet'),
          );
        }
        return ListTile(
          key: const Key('checkout-outlet'),
          leading: const Icon(Icons.store),
          title: Text(o.selected?.name ?? 'Pilih outlet'),
          subtitle: const Text('Outlet'),
          trailing: const Icon(Icons.chevron_right),
          enabled: enabled,
          onTap: () => showOutletPicker(context, ref, o),
        );
      },
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({required this.customer, required this.enabled});

  final Customer? customer;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: const Key('checkout-customer'),
      leading: const Icon(Icons.person_outline),
      title: Text(customer?.name ?? 'Walk-in'),
      subtitle: const Text('Pelanggan'),
      trailing: const Icon(Icons.chevron_right),
      enabled: enabled,
      onTap: () async {
        final choice = await showCustomerPicker(context);
        if (choice != null) ref.read(checkoutControllerProvider.notifier).setCustomer(choice.customer);
      },
    );
  }
}

class _CashSection extends ConsumerWidget {
  const _CashSection({required this.cash, required this.cart, required this.enabled, required this.onQuick});

  final TextEditingController cash;
  final Cart cart;
  final bool enabled;
  final void Function(int rupiah) onQuick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = ref.watch(checkoutControllerProvider.select((s) => s.cashReceived)) ?? 0;
    final total = cart.grandTotal.rupiahCeil;
    final change = received - total;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('cash-received'),
          controller: cash,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: const [RupiahInputFormatter()],
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          decoration: InputDecoration(labelText: 'Uang Diterima', prefixText: '${ref.watch(currencyFormatterProvider).symbol} '),
          onChanged: (text) => ref.read(checkoutControllerProvider.notifier).setCashReceived(parseRupiahInput(text)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in quickCashOptions(total))
              ActionChip(
                label: Text(amount == total ? 'Uang Pas' : ref.money(Money.rupiah(amount))),
                onPressed: enabled ? () => onQuick(amount) : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          color: change >= 0 && received > 0 ? Theme.of(context).colorScheme.secondaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Kembalian', style: textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      received == 0 ? '-' : change < 0 ? 'Kurang ${ref.money(Money.rupiah(-change))}' : ref.money(Money.rupiah(change)),
                      key: const Key('cash-change'),
                      style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when the payment request got no answer (timeout / lost
/// connection). Never offers a blind second submit.
class _UnknownOutcomeScaffold extends ConsumerWidget {
  const _UnknownOutcomeScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutControllerProvider);
    final controller = ref.read(checkoutControllerProvider.notifier);
    final recent = state.recent;
    final textTheme = Theme.of(context).textTheme;
    final busy = state.isCheckingRecent || state.isSubmitting;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Status Transaksi'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Icon(Icons.help_outline, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Status transaksi belum diketahui',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Server tidak sempat membalas. Transaksi mungkin sudah tersimpan. '
                    'Jangan menagih pelanggan dua kali.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (busy)
                    const Center(child: CircularProgressIndicator())
                  else if (recent == null) ...[
                    if (state.failure != null) MessageBanner(state.failure!.message),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: controller.checkRecent,
                      icon: const Icon(Icons.refresh),
                      label: const Text('CEK STATUS'),
                    ),
                  ] else if (recent.backendSupportsIdempotency) ...[
                    const MessageBanner(
                      'Transaksi belum ditemukan di server. Mengirim ulang aman: '
                      'server tidak akan membuat transaksi ganda.',
                      tone: BannerTone.info,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('checkout-resend'),
                      onPressed: controller.resend,
                      icon: const Icon(Icons.send),
                      label: const Text('KIRIM ULANG'),
                    ),
                  ] else ...[
                    const MessageBanner(
                      'Periksa daftar transaksi terakhir. Jika transaksi ini sudah ada, pilih transaksinya. '
                      'Kirim ulang hanya jika transaksi belum ada.',
                      tone: BannerTone.info,
                    ),
                    const SizedBox(height: 8),
                    for (final sale in recent.sales.take(5))
                      ListTile(
                        title: Text(sale.invoiceNumber),
                        subtitle: Text('${sale.paymentLabel} · ${sale.itemCount} item · ${sale.cashierName ?? ''}'),
                        trailing: Text(ref.money(sale.grandTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => controller.confirmRecorded(sale),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Kirim ulang transaksi?'),
                            content: const Text('Lanjutkan hanya jika transaksi ini tidak ada di daftar.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kirim Ulang')),
                            ],
                          ),
                        );
                        if (ok ?? false) await controller.resend();
                      },
                      child: const Text('Transaksi tidak ada, kirim ulang'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: busy ? null : controller.dismissUnknown,
                    child: const Text('Kembali ke pembayaran'),
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
