import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/cart.dart';
import '../../../domain/entities/product.dart';
import '../../auth/application/session_controller.dart';

enum CartChange { added, updated, removed, outOfStock, stockLimited }

/// What happened to a cart action, with a message for the cashier when the
/// action was limited.
class CartResult {
  const CartResult(this.change, [this.message]);

  final CartChange change;
  final String? message;

  bool get isLimited => change == CartChange.outOfStock || change == CartChange.stockLimited;
}

/// In-memory cart for the active tenant. Stock limits use the stock seen in
/// the catalog as a hint only; the backend re-validates stock at checkout.
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    // A different tenant (or logout) must never see this cart.
    ref.watch(activeTenantProvider);
    return const Cart();
  }

  CartResult add(Product product, {int qty = 1}) {
    if (product.isOutOfStock) {
      return CartResult(CartChange.outOfStock, '${product.name} sedang habis stok.');
    }
    final current = state.qtyOf(product.id);
    final result = _put(product, current + qty);
    return result.change == CartChange.updated && current == 0 ? const CartResult(CartChange.added) : result;
  }

  /// Sets an exact quantity; 0 or less removes the line.
  CartResult setQty(int productId, int qty) {
    final line = state.lineFor(productId);
    if (line == null) return const CartResult(CartChange.removed);
    return _put(line.product, qty);
  }

  CartResult increment(int productId) => setQty(productId, state.qtyOf(productId) + 1);

  CartResult decrement(int productId) => setQty(productId, state.qtyOf(productId) - 1);

  void remove(int productId) {
    state = Cart([for (final l in state.lines) if (l.product.id != productId) l]);
  }

  void clear() => state = const Cart();

  /// Refreshes price/stock snapshots of lines already in the cart with
  /// fresher catalog data, so the total preview stays accurate.
  void syncProducts(Iterable<Product> products) {
    if (state.isEmpty) return;
    final byId = {for (final p in products) p.id: p};
    if (!state.lines.any((l) => byId.containsKey(l.product.id))) return;
    state = Cart([for (final l in state.lines) byId[l.product.id] == null ? l : l.copyWith(product: byId[l.product.id])]);
  }

  CartResult _put(Product product, int qty) {
    if (qty <= 0) {
      remove(product.id);
      return const CartResult(CartChange.removed);
    }

    var change = CartChange.updated;
    String? message;
    var finalQty = qty;
    if (qty > product.stock) {
      finalQty = product.stock;
      change = CartChange.stockLimited;
      message = 'Stok ${product.name} tidak mencukupi (tersisa ${product.stock}).';
      if (finalQty <= 0) {
        remove(product.id);
        return CartResult(CartChange.outOfStock, '${product.name} sedang habis stok.');
      }
    }

    final exists = state.lineFor(product.id) != null;
    state = Cart(
      exists
          ? [for (final l in state.lines) l.product.id == product.id ? CartLine(product: product, qty: finalQty) : l]
          : [...state.lines, CartLine(product: product, qty: finalQty)],
    );
    return CartResult(change, message);
  }
}

final cartControllerProvider = NotifierProvider<CartController, Cart>(CartController.new);
