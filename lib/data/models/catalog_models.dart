import '../../core/utils/json.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/entities/product.dart';

/// Parses `ProductResource`. `cost_price` is intentionally not mapped: the
/// cashier UI never needs it.
abstract final class ProductModel {
  static Product fromJson(Map<String, dynamic> json) => Product(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        sku: Json.asString(json['sku']),
        barcode: _blankToNull(json['barcode']),
        categoryId: Json.asIntOrNull(json['category_id']),
        categoryName: Json.asStringOrNull(json['category_name']),
        unitName: Json.asStringOrNull(json['unit_name']),
        price: Money.fromJson(json['price']),
        stock: Json.asInt(json['stock']),
        minStock: Json.asInt(json['min_stock']),
        taxHundredths: Json.asHundredths(json['tax_percentage']),
        discountHundredths: Json.asHundredths(json['discount_percentage']),
        imageUrl: _blankToNull(json['image_url']),
        isActive: Json.asBool(json['is_active'], fallback: true),
      );

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
