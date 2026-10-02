import '../../core/utils/money.dart';

/// The cashier-relevant part of `GET /dashboard` `stats`. These figures are
/// tenant-wide (the backend does not scope them to a branch or cashier);
/// profit and cash-in-drawer are deliberately not exposed to the cashier UI.
class DashboardSummary {
  const DashboardSummary({
    required this.todaySales,
    required this.transactionsCount,
    required this.productsCount,
  });

  final Money todaySales;
  final int transactionsCount;
  final int productsCount;
}
