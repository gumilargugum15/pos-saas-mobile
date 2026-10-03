import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/party.dart';
import '../../domain/entities/sale.dart';
import '../../domain/repositories/sales_repository.dart';
import '../../features/auth/application/session_controller.dart';
import '../models/sale_models.dart';

class SalesRepositoryImpl implements SalesRepository, PartyRepository {
  SalesRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<CheckoutResult> checkout(CheckoutRequest request, {required String idempotencyKey}) async {
    final response = await _api.post(
      '/sales',
      body: request.toJson(),
      headers: {'Idempotency-Key': idempotencyKey},
      parse: (d) => SaleModel.fromJson(Json.asMap(d)),
    );
    return CheckoutResult(sale: response.data, replayed: response.statusCode == 200);
  }

  @override
  Future<Paginated<Sale>> list(SalesQuery query, {int page = 1, int perPage = 20}) {
    String? day(DateTime? d) => d == null
        ? null
        : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final search = query.search?.trim();
    return _api.getPage(
      '/sales',
      query: {
        'search': search == null || search.isEmpty ? null : search,
        'status': query.status?.apiValue,
        'payment_method': query.paymentMethod?.apiValue,
        'date_from': day(query.dateFrom),
        'date_to': day(query.dateTo),
        'branch_id': query.branchId,
        'sort': 'created_at',
        'direction': 'desc',
        'page': page,
        'per_page': perPage,
      },
      parseItem: SaleModel.fromJson,
    );
  }

  @override
  Future<Sale> detail(int id) async {
    final response = await _api.get('/sales/$id', parse: (d) => SaleModel.fromJson(Json.asMap(d)));
    return response.data;
  }

  @override
  Future<RecentSales> recent({int? branchId, int limit = 10}) async {
    var supportsIdempotency = false;
    final response = await _api.get(
      '/sales',
      query: {'branch_id': branchId, 'sort': 'created_at', 'direction': 'desc', 'per_page': limit},
      parse: (data) => [
        for (final raw in data as List)
          () {
            final json = Json.asMap(raw);
            // Only backends with the idempotency change serialize this key.
            if (json.containsKey('client_reference')) supportsIdempotency = true;
            return SaleModel.fromJson(json);
          }(),
      ],
    );
    return RecentSales(sales: response.data, backendSupportsIdempotency: supportsIdempotency);
  }

  @override
  Future<List<Branch>> branches() async {
    final page = await _api.getPage(
      '/branches',
      query: {'is_active': 1, 'sort': 'name', 'direction': 'asc', 'per_page': 100},
      parseItem: BranchModel.fromJson,
    );
    return page.items;
  }

  @override
  Future<Paginated<Customer>> customers({String? search, int page = 1, int perPage = 20}) {
    final term = search?.trim();
    return _api.getPage(
      '/customers',
      query: {
        'search': term == null || term.isEmpty ? null : term,
        'is_active': 1,
        'sort': 'name',
        'direction': 'asc',
        'page': page,
        'per_page': perPage,
      },
      parseItem: CustomerModel.fromJson,
    );
  }

  @override
  Future<Customer> createCustomer({required String name, String? phone, String? email, String? address}) async {
    String? blank(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final response = await _api.post(
      '/customers',
      body: {'name': name.trim(), 'phone': blank(phone), 'email': blank(email), 'address': blank(address)},
      parse: (d) => CustomerModel.fromJson(Json.asMap(d)),
    );
    return response.data;
  }
}

/// Rebuilt per active tenant.
final salesRepositoryProvider = Provider<SalesRepositoryImpl>((ref) {
  ref.watch(activeTenantProvider);
  return SalesRepositoryImpl(ref.watch(apiClientProvider));
});
