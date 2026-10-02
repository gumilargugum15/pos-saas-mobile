import '../../core/utils/money.dart';
import 'product.dart';

/// One cart line. The amounts replicate `SaleService::checkout` line by line
/// so the preview matches what the server will charge:
///
///   gross    = price × qty
///   discount = round(gross × discount% / 100, 2)
///   tax      = round((gross − discount) × tax% / 100, 2)
///   subtotal = gross − discount + tax
///
/// The server recomputes everything from current product data; after
/// checkout its numbers are the ones shown.
class CartLine {
  const CartLine({required this.product, required this.qty});

  final Product product;
  final int qty;

  Money get gross => product.price * qty;
  Money get discount => gross.percentOf(product.discountHundredths);
  Money get tax => (gross - discount).percentOf(product.taxHundredths);
  Money get subtotal => gross - discount + tax;

  /// More than the stock seen when the product was loaded.
  bool get exceedsKnownStock => qty > product.stock;

  CartLine copyWith({Product? product, int? qty}) =>
      CartLine(product: product ?? this.product, qty: qty ?? this.qty);
}

class Cart {
  const Cart([this.lines = const []]);

  final List<CartLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Total quantity of all lines.
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);

  /// Σ gross, the backend's `subtotal` (before discount and tax).
  Money get subtotal => lines.fold(const Money.zero(), (sum, l) => sum + l.gross);
  Money get discountTotal => lines.fold(const Money.zero(), (sum, l) => sum + l.discount);
  Money get taxTotal => lines.fold(const Money.zero(), (sum, l) => sum + l.tax);

  /// The backend's `grand_total`.
  Money get grandTotal => subtotal - discountTotal + taxTotal;

  CartLine? lineFor(int productId) => lines.where((l) => l.product.id == productId).firstOrNull;

  int qtyOf(int productId) => lineFor(productId)?.qty ?? 0;

  /// The request lines for `POST /sales`: only product ids and quantities.
  List<Map<String, int>> toSaleItems() => [
        for (final l in lines) {'product_id': l.product.id, 'qty': l.qty},
      ];
}
