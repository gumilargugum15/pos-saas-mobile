import '../../core/utils/money.dart';

/// A cashier's drawer session (`ShiftResource`).
class Shift {
  const Shift({
    required this.id,
    required this.isOpen,
    required this.openingBalance,
    this.closingBalance,
    this.expectedBalance,
    this.variance,
    this.openedAt,
    this.closedAt,
    this.branchName,
    this.userName,
    this.notes,
  });

  final int id;
  final bool isOpen;
  final Money openingBalance;

  /// Cash counted by the cashier at closing.
  final Money? closingBalance;

  /// Opening + cash sales + cash in − cash out, computed by the server.
  final Money? expectedBalance;

  /// closing − expected (negative = cash short).
  final Money? variance;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String? branchName;
  final String? userName;
  final String? notes;
}

/// Running totals of the open shift (`GET /shifts/current` → `live`).
class ShiftLive {
  const ShiftLive({
    required this.cashSales,
    required this.cashIn,
    required this.cashOut,
    required this.expectedBalance,
  });

  final Money cashSales;
  final Money cashIn;
  final Money cashOut;
  final Money expectedBalance;
}

enum CashDirection {
  cashIn('in', 'Kas Masuk'),
  cashOut('out', 'Kas Keluar');

  const CashDirection(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Categories allowed per direction (CashTransactionService). Labels match
/// the web finance page.
enum CashCategory {
  income('income', 'Pendapatan Lain', CashDirection.cashIn),
  deposit('deposit', 'Setoran Modal', CashDirection.cashIn),
  otherIn('other', 'Lainnya', CashDirection.cashIn),
  expense('expense', 'Biaya Operasional', CashDirection.cashOut),
  withdrawal('withdrawal', 'Penarikan Kas', CashDirection.cashOut),
  otherOut('other', 'Lainnya', CashDirection.cashOut);

  const CashCategory(this.apiValue, this.label, this.direction);

  final String apiValue;
  final String label;
  final CashDirection direction;

  static List<CashCategory> of(CashDirection direction) => values.where((c) => c.direction == direction).toList();

  static String labelOf(String type, String category) =>
      values.where((c) => c.direction.apiValue == type && c.apiValue == category).firstOrNull?.label ?? category;
}

/// A cash-in / cash-out entry (`CashTransactionResource`).
class CashMovement {
  const CashMovement({
    required this.id,
    required this.referenceNumber,
    required this.type,
    required this.category,
    required this.amount,
    required this.description,
    this.createdAt,
  });

  final int id;
  final String referenceNumber;

  /// `in` / `out`.
  final String type;
  final String category;
  final Money amount;
  final String description;
  final DateTime? createdAt;

  bool get isIn => type == 'in';
  String get categoryLabel => CashCategory.labelOf(type, category);
}
