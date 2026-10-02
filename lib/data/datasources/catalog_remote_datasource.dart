import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/entities/product.dart';
import '../models/catalog_models.dart';

class CatalogRemoteDataSource {
  const CatalogRemoteDataSource(this._api);

  final ApiClient _api;

  /// `GET /products` — `search` matches name, SKU and barcode (LIKE).
  Future<Paginated<Product>> products({String? search, int? categoryId, required int page, required int perPage}) {
    return _api.getPage(
      '/products',
      query: {
        'search': search,
        'category_id': categoryId,
        'is_active': 1,
        'sort': 'name',
        'direction': 'asc',
        'page': page,
        'per_page': perPage,
      },
      parseItem: ProductModel.fromJson,
    );
  }

  Future<Product> product(int id) async {
    final response = await _api.get('/products/$id', parse: (d) => ProductModel.fromJson(Json.asMap(d)));
    return response.data;
  }

  Future<List<Category>> categories() async {
    final page = await _api.getPage(
      '/categories',
      query: {'is_active': 1, 'sort': 'name', 'direction': 'asc', 'per_page': 100},
      parseItem: CategoryModel.fromJson,
    );
    return page.items;
  }

  Future<DashboardSummary> dashboard() async {
    final response = await _api.get('/dashboard', parse: (d) => DashboardSummaryModel.fromJson(Json.asMap(d)));
    return response.data;
  }

  Future<Map<String, String>> settings() async {
    final response = await _api.get(
      '/settings',
      parse: (d) => {for (final e in Json.asMap(d).entries) e.key: e.value?.toString() ?? ''},
    );
    return response.data;
  }
}
