import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/catalog_repository_impl.dart';
import '../../../domain/entities/dashboard_summary.dart';

/// Re-fetched each time the dashboard is opened (autoDispose) or pulled.
final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) {
  return ref.watch(dashboardRepositoryProvider).summary();
});
