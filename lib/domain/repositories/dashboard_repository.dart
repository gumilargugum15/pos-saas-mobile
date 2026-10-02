import '../entities/dashboard_summary.dart';

abstract interface class DashboardRepository {
  Future<DashboardSummary> summary();
}

abstract interface class SettingsRepository {
  /// `GET /settings`: flat string map (currency, company, receipt keys).
  Future<Map<String, String>> fetch();
}
