import 'dart:async';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/network/api_response.dart';
import '../../../data/repositories/sales_repository_impl.dart';
import '../../../domain/entities/sale.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../outlet/outlet_controller.dart';

enum DatePreset {
  today('Hari ini'),
  last7('7 hari'),
  last30('30 hari'),
  all('Semua'),
  custom('Pilih tanggal');

  const DatePreset(this.label);

  final String label;
}

class TransactionsFilter {
  const TransactionsFilter({
    this.search = '',
    this.datePreset = DatePreset.today,
    this.customRange,
    this.paymentMethod,
    this.status,
  });

  final String search;
  final DatePreset datePreset;
  final DateTimeRange? customRange;
  final PaymentMethod? paymentMethod;
  final SaleStatus? status;

  /// Inclusive day range sent as `date_from` / `date_to`.
  (DateTime?, DateTime?) dateRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (datePreset) {
      DatePreset.today => (today, today),
      DatePreset.last7 => (today.subtract(const Duration(days: 6)), today),
      DatePreset.last30 => (today.subtract(const Duration(days: 29)), today),
      DatePreset.all => (null, null),
      DatePreset.custom => (customRange?.start, customRange?.end),
    };
  }

  TransactionsFilter copyWith({
    String? search,
    DatePreset? datePreset,
    DateTimeRange? customRange,
    PaymentMethod? paymentMethod,
    bool clearPaymentMethod = false,
    SaleStatus? status,
    bool clearStatus = false,
  }) =>
      TransactionsFilter(
        search: search ?? this.search,
        datePreset: datePreset ?? this.datePreset,
        customRange: customRange ?? this.customRange,
        paymentMethod: clearPaymentMethod ? null : paymentMethod ?? this.paymentMethod,
        status: clearStatus ? null : status ?? this.status,
      );
}

class TransactionsState {
  const TransactionsState({
    this.filter = const TransactionsFilter(),
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = true,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.failure,
  });

  final TransactionsFilter filter;
  final List<Sale> items;
  final int page;
  final int total;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final AppFailure? failure;

  TransactionsState copyWith({
    TransactionsFilter? filter,
    List<Sale>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    AppFailure? failure,
    bool clearFailure = false,
  }) =>
      TransactionsState(
        filter: filter ?? this.filter,
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        failure: clearFailure ? null : failure ?? this.failure,
      );
}

/// Sales history for the active outlet. The backend scopes users with a
/// home branch to it; others see the outlet chosen on this device.
class TransactionsController extends Notifier<TransactionsState> {
  static const perPage = 20;
  int _query = 0;

  @override
  TransactionsState build() {
    ref.watch(salesRepositoryProvider);
    Future.microtask(_reload);
    return const TransactionsState();
  }

  void setFilter(TransactionsFilter filter) {
    state = state.copyWith(filter: filter);
    _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore || state.failure != null) return;
    final query = _query;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _fetch(state.page + 1);
      if (query != _query) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        page: page.meta.currentPage,
        hasMore: page.meta.hasMore,
        isLoadingMore: false,
      );
    } on AppFailure catch (failure) {
      if (query == _query) state = state.copyWith(isLoadingMore: false, failure: failure);
    }
  }

  Future<void> _reload() async {
    final query = ++_query;
    state = state.copyWith(isLoading: true, isLoadingMore: false, clearFailure: true);
    try {
      final page = await _fetch(1);
      if (query != _query) return;
      state = state.copyWith(
        items: page.items,
        page: page.meta.currentPage,
        total: page.meta.total,
        hasMore: page.meta.hasMore,
        isLoading: false,
      );
    } on AppFailure catch (failure) {
      if (query == _query) state = state.copyWith(items: const [], isLoading: false, hasMore: false, failure: failure);
    }
  }

  Future<Paginated<Sale>> _fetch(int page) async {
    int? branchId;
    try {
      branchId = (await ref.read(outletControllerProvider.future)).requestBranchId;
    } on AppFailure {
      branchId = null;
    }
    final filter = state.filter;
    final (from, to) = filter.dateRange(DateTime.now());
    return ref.read(salesRepositoryProvider).list(
          SalesQuery(
            search: filter.search,
            status: filter.status,
            paymentMethod: filter.paymentMethod,
            dateFrom: from,
            dateTo: to,
            branchId: branchId,
          ),
          page: page,
          perPage: perPage,
        );
  }
}

final transactionsControllerProvider =
    NotifierProvider.autoDispose<TransactionsController, TransactionsState>(TransactionsController.new);

final saleDetailProvider = FutureProvider.autoDispose.family<Sale, int>((ref, id) {
  return ref.watch(salesRepositoryProvider).detail(id);
});
