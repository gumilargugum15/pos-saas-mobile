import '../../core/utils/money.dart';

/// A sellable product (`ProductResource`). [stock] is a snapshot: the
/// backend re-checks stock under a row lock at checkout.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.price,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.unitId,
    this.unitName,
    this.costPrice,
    this.stock = 0,
    this.minStock = 0,
    this.taxHundredths = 0,
    this.discountHundredths = 0,
    this.imageUrl,
    this.isActive = true,
  });

  final int id;
  final String name;
  final String sku;
  final String? barcode;
  final int? categoryId;
  final String? categoryName;
  final int? brandId;
  final String? brandName;
  final int? unitId;
  final String? unitName;

  /// Purchase price. Only used by the product edit form (manage-products);
  /// never shown on cashier screens.
  final Money? costPrice;
  final Money price;
  final int stock;
  final int minStock;

  /// `tax_percentage` × 100 (11% → 1100).
  final int taxHundredths;

  /// `discount_percentage` × 100 (10% → 1000).
  final int discountHundredths;
  final String? imageUrl;
  final bool isActive;

  bool get isOutOfStock => stock <= 0;
  bool get isLowStock => stock <= minStock;
  bool get hasDiscount => discountHundredths > 0;

  /// Price after the product's own discount, before tax (display only).
  Money get discountedPrice => price - price.percentOf(discountHundredths);

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

String formatPercent(int hundredths) {
  final whole = hundredths ~/ 100;
  final fraction = hundredths % 100;
  if (fraction == 0) return '$whole%';
  return '$whole,${fraction.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
}
