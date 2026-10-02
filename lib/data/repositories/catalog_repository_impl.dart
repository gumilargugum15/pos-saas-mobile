import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../../domain/usecases/match_scanned_code.dart';
import '../../features/auth/application/session_controller.dart';
import '../datasources/catalog_remote_datasource.dart';

/// Remote-only for now. Offline catalog caching would add a local data
/// source behind this same interface (docs/PROJECT_ANALYSIS.md §11);
/// categories are kept in memory for the session because they rarely change.
class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._remote);

  final CatalogRemoteDataSource _remote;
  List<Category>? _categories;

  @override
  Future<Paginated<Product>> products({String? search, int? categoryId, int page = 1, int perPage = 50}) {
    final term = search?.trim();
    return _remote.products(
      search: term == null || term.isEmpty ? null : term,
      categoryId: categoryId,
      page: page,
      perPage: perPage,
    );
  }

  @override
  Future<Product> product(int id) => _remote.product(id);

  @override
  Future<Product?> findByCode(String code) async {
    final term = code.trim();
    if (term.isEmpty) return null;
    // Same lookup as the web POS: a narrow search, then an exact match.
    final page = await _remote.products(search: term, page: 1, perPage: 10);
    return matchScannedCode(page.items, term);
  }

  @override
  Future<List<Category>> categories() async => _categories ??= await _remote.categories();
}

class DashboardRepositoryImpl implements DashboardRepository, SettingsRepository {
  DashboardRepositoryImpl(this._remote);

  final CatalogRemoteDataSource _remote;

  @override
  Future<DashboardSummary> summary() => _remote.dashboard();

  @override
  Future<Map<String, String>> fetch() => _remote.settings();
}

/// Rebuilt when the active tenant changes, so no cached data crosses tenants.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  ref.watch(activeTenantProvider);
  return CatalogRepositoryImpl(CatalogRemoteDataSource(ref.watch(apiClientProvider)));
});

final dashboardRepositoryProvider = Provider<DashboardRepositoryImpl>((ref) {
  ref.watch(activeTenantProvider);
  return DashboardRepositoryImpl(CatalogRemoteDataSource(ref.watch(apiClientProvider)));
});
