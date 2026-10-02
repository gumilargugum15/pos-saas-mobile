import '../../core/network/api_response.dart';
import '../entities/category.dart';
import '../entities/product.dart';

/// Read-only catalog access for the cashier. Every method throws
/// `AppFailure` on error.
abstract interface class CatalogRepository {
  /// Active products, optionally filtered by text (name / SKU / barcode)
  /// and category.
  Future<Paginated<Product>> products({String? search, int? categoryId, int page = 1, int perPage = 50});

  Future<Product> product(int id);

  /// The active product whose barcode or SKU is exactly [code], or null.
  Future<Product?> findByCode(String code);

  Future<List<Category>> categories();
}
