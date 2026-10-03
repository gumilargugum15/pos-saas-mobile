import '../../core/utils/money.dart';

/// Payment methods accepted by `POST /sales` (StoreSaleRequest:
/// `in:cash,debit,credit_card,transfer,qris,e_wallet`). There is no payment
/// table or gateway in the backend: non-cash methods are recorded labels.
enum PaymentMethod {
  cash('cash', 'Tunai'),
  debit('debit', 'Debit'),
  creditCard('credit_card', 'Kartu Kredit'),
  transfer('transfer', 'Transfer'),
  qris('qris', 'QRIS'),
  eWallet('e_wallet', 'E-Wallet');

  const PaymentMethod(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isCash => this == PaymentMethod.cash;

  static PaymentMethod? fromApi(String? value) => values.where((m) => m.apiValue == value).firstOrNull;

  /// Label for any backend value, including unknown future ones.
  static String labelOf(String? value) => fromApi(value)?.label ?? (value ?? '-').replaceAll('_', ' ');
}

enum SaleStatus {
  paid('paid', 'Lunas'),
  refunded('refunded', 'Direfund'),
  voided('void', 'Batal'),
  pending('pending', 'Tertunda');

  const SaleStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static SaleStatus fromApi(String? value) =>
      values.where((s) => s.apiValue == value).firstOrNull ?? SaleStatus.pending;
}

class SaleItem {
  const SaleItem({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.price,
    required this.discount,
    required this.tax,
    required this.subtotal,
  });

  final int productId;

  /// Name at the time of sale (snapshot).
  final String productName;
  final int qty;
  final Money price;
  final Money discount;
  final Money tax;

  /// gross − discount + tax.
  final Money subtotal;

  Money get gross => price * qty;
}

/// A completed sale as stored by the backend (`SaleResource`). Every amount
/// and the invoice number come from the server.
class Sale {
  const Sale({
    required this.id,
    required this.invoiceNumber,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.grandTotal,
    required this.paid,
    required this.change,
    required this.paymentMethod,
    required this.status,
    this.clientReference,
    this.branchId,
    this.branchName,
    this.customerId,
    this.customerName,
    this.cashierName,
    this.items = const [],
    this.createdAt,
  });

  final int id;
  final String invoiceNumber;

  /// The Idempotency-Key this sale was created with (null for web sales and
  /// on backends without idempotency support).
  final String? clientReference;
  final int? branchId;
  final String? branchName;
  final int? customerId;

  /// Null means walk-in.
  final String? customerName;
  final String? cashierName;
  final List<SaleItem> items;
  final Money subtotal;
  final Money discount;
  final Money tax;
  final Money grandTotal;
  final Money paid;
  final Money change;

  /// Raw backend value (see [PaymentMethod]).
  final String paymentMethod;
  final SaleStatus status;
  final DateTime? createdAt;

  String get paymentLabel => PaymentMethod.labelOf(paymentMethod);
  String get customerLabel => customerName ?? 'Walk-in';
  int get itemCount => items.fold(0, (sum, i) => sum + i.qty);
}
