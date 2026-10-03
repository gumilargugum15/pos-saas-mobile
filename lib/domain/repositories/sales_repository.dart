import '../../core/network/api_response.dart';
import '../entities/party.dart';
import '../entities/sale.dart';

/// What the cashier submits. Prices, discounts, tax and totals are never
/// sent: the backend computes them from current product data.
class CheckoutRequest {
  const CheckoutRequest({
    required this.items,
    required this.paymentMethod,
    required this.paidRupiah,
    this.customerId,
    this.branchId,
  });

  final List<Map<String, int>> items;
  final PaymentMethod paymentMethod;

  /// Whole rupiah handed over (cash) or charged (non-cash).
  final int paidRupiah;
  final int? customerId;
  final int? branchId;

  Map<String, Object?> toJson() => {
        'branch_id': branchId,
        'customer_id': customerId,
        'items': items,
        'payment_method': paymentMethod.apiValue,
        'paid_amount': paidRupiah,
      };

  /// Identifies "the same checkout" for idempotency-key reuse.
  String get fingerprint => [
        branchId,
        customerId,
        paymentMethod.apiValue,
        paidRupiah,
        for (final i in items) '${i['product_id']}x${i['qty']}',
      ].join('|');
}

class CheckoutResult {
  const CheckoutResult({required this.sale, required this.replayed});

  final Sale sale;

  /// True when the server returned a sale it had already created for this
  /// Idempotency-Key (HTTP 200 instead of 201).
  final bool replayed;
}

class RecentSales {
  const RecentSales({required this.sales, required this.backendSupportsIdempotency});

  final List<Sale> sales;

  /// The backend exposes `client_reference` (feature/sales-idempotency), so
  /// re-sending with the same Idempotency-Key cannot create a duplicate.
  final bool backendSupportsIdempotency;
}

class SalesQuery {
  const SalesQuery({this.search, this.status, this.paymentMethod, this.dateFrom, this.dateTo, this.branchId});

  final String? search;
  final SaleStatus? status;
  final PaymentMethod? paymentMethod;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? branchId;
}

/// Every method throws `AppFailure` on error.
abstract interface class SalesRepository {
  /// `POST /sales` with the `Idempotency-Key` header.
  Future<CheckoutResult> checkout(CheckoutRequest request, {required String idempotencyKey});

  Future<Paginated<Sale>> list(SalesQuery query, {int page = 1, int perPage = 20});

  Future<Sale> detail(int id);

  /// Most recent sales first; used to resolve an unknown checkout outcome.
  Future<RecentSales> recent({int? branchId, int limit = 10});
}

abstract interface class PartyRepository {
  Future<List<Branch>> branches();

  Future<Paginated<Customer>> customers({String? search, int page = 1, int perPage = 20});

  /// Requires `manage-customers`.
  Future<Customer> createCustomer({required String name, String? phone, String? email, String? address});
}
