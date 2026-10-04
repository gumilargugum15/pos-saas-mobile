import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/cart.dart';
import '../../settings/settings_providers.dart';
import '../application/cart_controller.dart';
import 'held_carts_widgets.dart';

/// Lines, totals and the checkout action. Used as the right pane on
/// tablets and as the body of the cart screen on phones.
Future<void> confirmClearCart(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kosongkan keranjang?'),
      content: const Text('Semua produk di keranjang akan dihapus.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kosongkan')),
      ],
    ),
  );
  if (ok ?? false) ref.read(cartControllerProvider.notifier).clear();
}

class CartPane extends ConsumerWidget {
  const CartPane({super.key, required this.onCheckout, this.showHeader = true});

  final VoidCallback onCheckout;

  /// False when the screen's app bar already shows the title (phone).
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cart.isEmpty ? 'Keranjang' : 'Keranjang (${cart.itemCount})',
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (cart.isNotEmpty)
                  TextButton.icon(
                    key: const Key('cart-clear'),
                    onPressed: () => confirmClearCart(context, ref),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Kosongkan'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: cart.isEmpty
              ? const StatusView(
                  icon: Icons.shopping_cart_outlined,
                  message: 'Keranjang masih kosong.\nPilih atau scan produk.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => CartLineTile(line: cart.lines[i]),
                ),
        ),
        CartTotals(cart: cart),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              // Web "Hold": park this cart and serve the next customer.
              OutlinedButton.icon(
                key: const Key('cart-hold'),
                onPressed: cart.isEmpty ? null : () => holdCurrentCart(context, ref),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 60)),
                icon: const Icon(Icons.pause),
                label: const Text('TAHAN'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('cart-checkout'),
                  onPressed: cart.isEmpty ? null : onCheckout,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  child: const Text('CHECKOUT'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CartLineTile extends ConsumerWidget {
  const CartLineTile({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(cartControllerProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final product = line.product;

    void report(CartResult result) {
      if (result.isLimited) showQuickMessage(context, result.message!, isError: true);
    }

    return Dismissible(
      key: ValueKey('line-${product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => controller.remove(product.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${ref.money(product.price)} × ${line.qty}', style: textTheme.bodySmall),
                  Text(ref.money(line.gross), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            _QtyStepper(
              qty: line.qty,
              onMinus: () => report(controller.decrement(product.id)),
              onPlus: () => report(controller.increment(product.id)),
              onTapQty: () async {
                final qty = await showQtyDialog(context, initial: line.qty, max: product.stock, name: product.name);
                if (qty != null) report(controller.setQty(product.id, qty));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onMinus, required this.onPlus, required this.onTapQty});

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapQty;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: qty == 1 ? 'Hapus' : 'Kurangi',
          onPressed: onMinus,
          icon: Icon(qty == 1 ? Icons.delete_outline : Icons.remove),
        ),
        InkWell(
          onTap: onTapQty,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            alignment: Alignment.center,
            child: Text('$qty', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
        IconButton.filledTonal(tooltip: 'Tambah', onPressed: onPlus, icon: const Icon(Icons.add)),
      ],
    );
  }
}

class CartTotals extends ConsumerWidget {
  const CartTotals({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: strong ? textTheme.titleMedium : textTheme.bodyMedium),
          const SizedBox(width: 12),
          // Large amounts / large system fonts shrink instead of overflowing.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: strong
                    ? textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)
                    : textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          row('Subtotal', ref.money(cart.subtotal)),
          row(
            'Diskon',
            cart.discountTotal.isZero ? ref.money(cart.discountTotal) : '-${ref.money(cart.discountTotal)}',
          ),
          row('Pajak', ref.money(cart.taxTotal)),
          const Divider(height: 16),
          row('TOTAL', ref.money(cart.grandTotal), strong: true),
          if (cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Estimasi. Harga, diskon, pajak, dan stok dipastikan oleh server saat checkout.',
                style: textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact bottom bar on phones: item count + total, opens the cart.
class CartSummaryBar extends ConsumerWidget {
  const CartSummaryBar({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(KagoemTokens.radius2xl));
    // Web mobile cart bar: "rounded-2xl bg-primary px-5 py-3.5 shadow-brand"
    // with the count in a translucent pill.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Material(
            color: scheme.primary,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('cart-open'),
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                    child: Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shopping_cart_outlined, size: 18, color: scheme.onPrimary),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    cart.isEmpty ? 'Keranjang kosong' : '${cart.itemCount} item',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              ref.money(cart.grandTotal),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, color: scheme.onPrimary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Manual quantity entry. Returns null when cancelled.
Future<int?> showQtyDialog(BuildContext context, {required int initial, required int max, required String name}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _QtyDialog(initial: initial, max: max, name: name),
  );
}

class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.initial, required this.max, required this.name});

  final int initial;
  final int max;
  final String name;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}')
    ..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.initial}'.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = int.tryParse(_controller.text);
    if (qty != null && qty >= 0) Navigator.pop(context, qty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: TextField(
        key: const Key('qty-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        decoration: InputDecoration(labelText: 'Jumlah', helperText: 'Stok tersedia: ${widget.max} · 0 = hapus'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}
