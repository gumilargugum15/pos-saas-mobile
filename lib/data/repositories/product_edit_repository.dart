import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/product.dart';
import '../../features/auth/application/session_controller.dart';
import '../models/catalog_models.dart';

/// An id/name pair for the brand and unit dropdowns.
class LookupItem {
  const LookupItem(this.id, this.name);

  final int id;
  final String name;
}

/// Product changes to send. Only non-null fields are sent: the backend
/// validates every field with `sometimes` (UpdateProductRequest), so a
/// partial update leaves the rest untouched.
class ProductChanges {
  const ProductChanges({
    this.name,
    this.sku,
    this.barcode,
    this.clearBarcode = false,
    this.categoryId,
    this.brandId,
    this.unitId,
    this.priceRupiah,
    this.costPriceRupiah,
    this.stock,
    this.minStock,
    this.taxPercent,
    this.discountPercent,
    this.isActive,
    this.imagePath,
  });

  final String? name;
  final String? sku;
  final String? barcode;

  /// Remove the barcode (sent as an empty value → null on the server).
  final bool clearBarcode;
  final int? categoryId;
  final int? brandId;
  final int? unitId;
  final int? priceRupiah;
  final int? costPriceRupiah;
  final int? stock;
  final int? minStock;

  /// Decimal strings as typed, e.g. "11" or "12.5".
  final String? taxPercent;
  final String? discountPercent;
  final bool? isActive;

  /// Local file of a new product photo.
  final String? imagePath;

  bool get isEmpty => toFields().isEmpty && imagePath == null;

  /// Multipart text fields, in the same format the web admin sends.
  Map<String, String> toFields() => {
        'name': ?name,
        'sku': ?sku,
        'barcode': ?barcode,
        if (clearBarcode) 'barcode': '',
        if (categoryId != null) 'category_id': '$categoryId',
        if (brandId != null) 'brand_id': '$brandId',
        if (unitId != null) 'unit_id': '$unitId',
        if (priceRupiah != null) 'price': '$priceRupiah',
        if (costPriceRupiah != null) 'cost_price': '$costPriceRupiah',
        if (stock != null) 'stock': '$stock',
        if (minStock != null) 'min_stock': '$minStock',
        'tax_percentage': ?taxPercent,
        'discount_percentage': ?discountPercent,
        if (isActive != null) 'is_active': isActive! ? '1' : '0',
      };
}

/// Product editing for users with `manage-products` (Admin / Owner).
/// Every method throws `AppFailure` on error.
class ProductEditRepository {
  ProductEditRepository(this._api);

  final ApiClient _api;

  /// `PUT /products/{id}` sent as multipart `POST` + `_method=PUT`, like
  /// the web admin: PHP only parses file uploads on POST.
  Future<Product> update(int productId, ProductChanges changes) async {
    final form = FormData.fromMap({
      '_method': 'PUT',
      ...changes.toFields(),
      if (changes.imagePath != null)
        'image': await MultipartFile.fromFile(changes.imagePath!, filename: changes.imagePath!.split('/').last),
    });
    final response = await _api.post(
      '/products/$productId',
      body: form,
      parse: (d) => ProductModel.fromJson(Json.asMap(d)),
    );
    return response.data;
  }

  Future<List<LookupItem>> brands() => _lookup('/brands', {'is_active': 1});

  /// Units have no active flag in the backend.
  Future<List<LookupItem>> units() => _lookup('/units', const {});

  Future<List<LookupItem>> _lookup(String path, Map<String, dynamic> filter) async {
    final page = await _api.getPage(
      path,
      query: {...filter, 'sort': 'name', 'direction': 'asc', 'per_page': 100},
      parseItem: (j) => LookupItem(Json.asInt(j['id']), Json.asString(j['name'])),
    );
    return page.items;
  }
}

final productEditRepositoryProvider = Provider<ProductEditRepository>((ref) {
  ref.watch(activeTenantProvider);
  return ProductEditRepository(ref.watch(apiClientProvider));
});

final brandOptionsProvider = FutureProvider.autoDispose<List<LookupItem>>(
  (ref) => ref.watch(productEditRepositoryProvider).brands(),
);

final unitOptionsProvider = FutureProvider.autoDispose<List<LookupItem>>(
  (ref) => ref.watch(productEditRepositoryProvider).units(),
);
