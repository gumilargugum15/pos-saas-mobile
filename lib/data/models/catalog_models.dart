import '../../core/utils/json.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/entities/product.dart';

/// Parses `ProductResource`. `cost_price` is kept for the product edit form
/// only; cashier screens never display it.
abstract final class ProductModel {
  static Product fromJson(Map<String, dynamic> json) => Product(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        sku: Json.asString(json['sku']),
        barcode: _blankToNull(json['barcode']),
        categoryId: Json.asIntOrNull(json['category_id']),
        categoryName: Json.asStringOrNull(json['category_name']),
        brandId: Json.asIntOrNull(json['brand_id']),
        brandName: Json.asStringOrNull(json['brand_name']),
        unitId: Json.asIntOrNull(json['unit_id']),
        unitName: Json.asStringOrNull(json['unit_name']),
        costPrice: json['cost_price'] == null ? null : Money.fromJson(json['cost_price']),
        price: Money.fromJson(json['price']),
        stock: Json.asInt(json['stock']),
        minStock: Json.asInt(json['min_stock']),
        taxHundredths: Json.asHundredths(json['tax_percentage']),
        discountHundredths: Json.asHundredths(json['discount_percentage']),
        imageUrl: _blankToNull(json['image_url']),
        isActive: Json.asBool(json['is_active'], fallback: true),
      );

  /// The inverse of [fromJson] (same shape as `ProductResource`), used to
  /// keep product snapshots of held carts on the device. Amounts are written
  /// as decimal strings so they round-trip exactly.
  static Map<String, dynamic> toJson(Product p) => {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
        'barcode': p.barcode,
        'category_id': p.categoryId,
        'category_name': p.categoryName,
        'brand_id': p.brandId,
        'brand_name': p.brandName,
        'unit_id': p.unitId,
        'unit_name': p.unitName,
        'price': p.price.toDecimalString(),
        'stock': p.stock,
        'min_stock': p.minStock,
        'tax_percentage': _percent(p.taxHundredths),
        'discount_percentage': _percent(p.discountHundredths),
        'image_url': p.imageUrl,
        'is_active': p.isActive,
      };

  static String _percent(int hundredths) =>
      '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';

  static String? _blankToNull(Object? value) {
    final s = Json.asStringOrNull(value)?.trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// Parses `CategoryResource`.
abstract final class CategoryModel {
  static Category fromJson(Map<String, dynamic> json) =>
      Category(id: Json.asInt(json['id']), name: Json.asString(json['name']));
}

/// Parses `DashboardService::summary()['stats']`.
abstract final class DashboardSummaryModel {
  static DashboardSummary fromJson(Map<String, dynamic> json) {
    final stats = Json.asMap(json['stats']);
    return DashboardSummary(
      todaySales: Money.fromJson(stats['today_sales']),
      transactionsCount: Json.asInt(stats['transactions_count']),
      productsCount: Json.asInt(stats['products_count']),
    );
  }
}
