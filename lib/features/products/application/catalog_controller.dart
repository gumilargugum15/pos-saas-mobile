import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/repositories/catalog_repository_impl.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/repositories/catalog_repository.dart';
import '../../cart/application/cart_controller.dart';

class CatalogState {
  const CatalogState({
    this.search = '',
    this.categoryId,
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.failure,
  });

  final String search;
  final int? categoryId;
  final List<Product> items;
  final int page;
  final bool hasMore;

  /// First page (or a new query) is loading.
  final bool isLoading;
  final bool isLoadingMore;
  final AppFailure? failure;

  bool get isEmpty => !isLoading && failure == null && items.isEmpty;

  CatalogState copyWith({
    String? search,
    int? categoryId,
    bool clearCategory = false,
    List<Product>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    AppFailure? failure,
    bool clearFailure = false,
  }) =>
      CatalogState(
        search: search ?? this.search,
        categoryId: clearCategory ? null : categoryId ?? this.categoryId,
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        failure: clearFailure ? null : failure ?? this.failure,
      );
}

/// Paginated, searchable product list (infinite scroll).
class CatalogController extends Notifier<CatalogState> {
  static const perPage = 50;

  late CatalogRepository _repo;

  /// Responses for an older query are dropped.
  int _query = 0;

  @override
  CatalogState build() {
    _repo = ref.watch(catalogRepositoryProvider);
    Future.microtask(_reload);
    return const CatalogState(isLoading: true);
  }

  void setSearch(String search) {
    if (search.trim() == state.search) return;
    state = state.copyWith(search: search.trim());
    _reload();
  }

  void setCategory(int? categoryId) {
    if (categoryId == state.categoryId) return;
    state = categoryId == null ? state.copyWith(clearCategory: true) : state.copyWith(categoryId: categoryId);
    _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore || state.failure != null) return;
    final query = _query;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.products(
        search: state.search,
        categoryId: state.categoryId,
        page: state.page + 1,
        perPage: perPage,
      );
      if (query != _query) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        page: page.meta.currentPage,
        hasMore: page.meta.hasMore,
        isLoadingMore: false,
      );
      ref.read(cartControllerProvider.notifier).syncProducts(page.items);
    } on AppFailure catch (failure) {
      if (query != _query) return;
      // Keep what is shown; a later scroll retries.
      state = state.copyWith(isLoadingMore: false, failure: failure);
    }
  }

  /// Clears an error shown under the list and retries the next page.
  Future<void> retryMore() async {
    state = state.copyWith(clearFailure: true);
    await loadMore();
  }

  Future<void> _reload() async {
    final query = ++_query;
    state = state.copyWith(isLoading: true, isLoadingMore: false, clearFailure: true, page: 0, hasMore: true);
    try {
      final page = await _repo.products(search: state.search, categoryId: state.categoryId, page: 1, perPage: perPage);
      if (query != _query) return;
      state = state.copyWith(items: page.items, page: page.meta.currentPage, hasMore: page.meta.hasMore, isLoading: false);
      ref.read(cartControllerProvider.notifier).syncProducts(page.items);
    } on AppFailure catch (failure) {
      if (query != _query) return;
      state = state.copyWith(items: const [], isLoading: false, failure: failure, hasMore: false);
    }
  }
}

final catalogControllerProvider = NotifierProvider<CatalogController, CatalogState>(CatalogController.new);

final categoriesProvider = FutureProvider<List<Category>>((ref) => ref.watch(catalogRepositoryProvider).categories());

/// Barcode / exact-code lookup used by the scanner and hardware scanners.
final productLookupProvider = Provider<Future<Product?> Function(String code)>((ref) {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.findByCode;
});
