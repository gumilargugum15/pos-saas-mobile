import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/currency_formatter.dart';
import '../../core/utils/money.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../auth/application/session_controller.dart';

/// `GET /settings` (global in the backend, not per tenant). Loaded once per
/// session; empty while not logged in.
final settingsProvider = FutureProvider<Map<String, String>>((ref) async {
  if (ref.watch(activeTenantProvider) == null) return const {};
  return ref.watch(dashboardRepositoryProvider).fetch();
});

/// The only formatter widgets use. Falls back to the backend defaults
/// (Rp, dots, no decimals) until — or if — settings cannot be loaded.
final currencyFormatterProvider = Provider<CurrencyFormatter>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return settings == null || settings.isEmpty ? const CurrencyFormatter() : CurrencyFormatter.fromSettings(settings);
});

/// `ref.money(amount)` inside a widget's build method.
extension MoneyFormatting on WidgetRef {
  String money(Money amount) => watch(currencyFormatterProvider).format(amount);
}
