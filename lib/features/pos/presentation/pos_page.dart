import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/responsive.dart';
import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/product.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/presentation/cart_widgets.dart';
import '../../products/presentation/catalog_pane.dart';
import '../../products/presentation/product_widgets.dart';
import '../application/scan_to_cart.dart';

/// The cashier's main screen.
///
/// - Phone: catalog full screen, cart summary bar → cart screen.
/// - Tablet (≥ 840dp): catalog | cart side by side.
class PosPage extends ConsumerWidget {
  const PosPage({super.key});

  static const cartRoute = '/pos/cart';
  static const scanRoute = '/pos/scan';
  static const checkoutRoute = '/pos/checkout';

  void _add(BuildContext context, WidgetRef ref, Product product) {
    final result = ref.read(cartControllerProvider.notifier).add(product);
    if (result.isLimited) showQuickMessage(context, result.message!, isError: true);
  }

  /// Hardware scanners type the code and press Enter in the search field.
  Future<bool> _submitCode(BuildContext context, WidgetRef ref, String code) async {
    final outcome = await ref.read(scanToCartProvider)(code);
    if (!context.mounted) return false;
    switch (outcome.status) {
      case ScanStatus.added:
        showQuickMessage(context, outcome.message);
        return true;
      case ScanStatus.limited:
        showQuickMessage(context, outcome.message, isError: true);
        return true;
      case ScanStatus.notFound:
        // Not an exact code: leave the text as a normal search.
        return false;
      case ScanStatus.failed:
        showQuickMessage(context, outcome.message, isError: true);
        return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoPane = WindowSize.of(context).isExpanded;

    final catalog = CatalogPane(
      autofocusSearch: twoPane,
      onProductTap: (p) => _add(context, ref, p),
      onProductLongPress: (p) => showProductDetail(context, p, onAdd: () => _add(context, ref, p)),
      onSubmitCode: (code) => _submitCode(context, ref, code),
      onScanPressed: () => context.push(scanRoute),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Baru')),
      body: SafeArea(
        child: twoPane
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: catalog),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 400, child: CartPane(onCheckout: () => context.push(checkoutRoute))),
                ],
              )
            : catalog,
      ),
      bottomNavigationBar: twoPane ? null : CartSummaryBar(onOpen: () => context.push(cartRoute)),
    );
  }
}

/// Phone-only cart screen.
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(cart.isEmpty ? 'Keranjang' : 'Keranjang (${cart.itemCount})'),
        actions: [
          if (cart.isNotEmpty)
            TextButton.icon(
              key: const Key('cart-clear'),
              onPressed: () => confirmClearCart(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Kosongkan'),
            ),
        ],
      ),
      body: SafeArea(
        child: CartPane(showHeader: false, onCheckout: () => context.push(PosPage.checkoutRoute)),
      ),
    );
  }
}
