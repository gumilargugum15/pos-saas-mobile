import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppEnvironment { development, staging, production }

/// Which backend product this build talks to. One codebase, two apps
/// (Android product flavors `saas` and `cashier`):
///
/// - [saas]: Kagoem POS SaaS — multi-tenant (`/tenants`, `X-Tenant-ID`,
///   plan modules).
/// - [cashier]: pos-cashier (e.g. Warung Epon) — the single-store
///   predecessor of the same backend: identical API minus tenancy.
enum AppVariant { saas, cashier }

/// Build-time configuration, injected with `--flavor <variant>` and
/// `--dart-define-from-file=env/<file>.json` (see README).
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.variant = AppVariant.saas,
    this.appName = 'Kagoem POS',
    this.salesDateFilter = true,
  });

  final AppEnvironment environment;

  /// Includes the API version prefix, e.g. `https://pos.example.com/api/v1`.
  final String apiBaseUrl;
  final AppVariant variant;

  /// Store / app name shown in the app (e.g. "Warung Epon").
  final String appName;

  /// The backend accepts `date_from` / `date_to` on `GET /sales`
  /// (kagoem-pos-saas since feature/sales-idempotency). When false the
  /// history hides its date filter instead of pretending to filter.
  final bool salesDateFilter;

  bool get isProduction => environment == AppEnvironment.production;

  /// Tenant selection and `X-Tenant-ID` exist only on the SaaS backend.
  bool get multiTenant => variant == AppVariant.saas;

  /// Throws [ConfigException] when the build was made without a valid
  /// environment file, so a misconfigured build fails loudly at startup
  /// instead of calling a wrong server.
  factory AppConfig.fromEnvironment() {
    const envName = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const baseUrl = String.fromEnvironment('API_BASE_URL');
    const appName = String.fromEnvironment('APP_NAME');
    const dateFilter = String.fromEnvironment('SALES_DATE_FILTER');

    return AppConfig.parse(
      envName: envName,
      baseUrl: baseUrl,
      flavor: appFlavor,
      appName: appName,
      salesDateFilter: dateFilter,
    );
  }

  factory AppConfig.parse({
    required String envName,
    required String baseUrl,
    String? flavor,
    String? appName,
    String? salesDateFilter,
  }) {
    final environment = AppEnvironment.values
        .where((e) => e.name == envName)
        .firstOrNull;
    if (environment == null) {
      throw ConfigException('APP_ENV tidak dikenal: "$envName".');
    }

    final variant = flavor == null || flavor.isEmpty
        ? AppVariant.saas
        : AppVariant.values.where((v) => v.name == flavor).firstOrNull;
    if (variant == null) {
      throw ConfigException('Flavor tidak dikenal: "$flavor".');
    }

    final uri = Uri.tryParse(baseUrl.trim());
    if (baseUrl.trim().isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ConfigException(
        'API_BASE_URL belum diatur. Jalankan dengan '
        '--dart-define-from-file=env/<environment>.json',
      );
    }
    if (environment != AppEnvironment.development && uri.scheme != 'https') {
      throw ConfigException('API_BASE_URL untuk ${environment.name} wajib https.');
    }

    final name = appName?.trim() ?? '';
    final dateFilter = salesDateFilter?.trim().toLowerCase() ?? '';

    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return AppConfig(
      environment: environment,
      apiBaseUrl: normalized,
      variant: variant,
      appName: name.isNotEmpty ? name : (variant == AppVariant.saas ? 'Kagoem POS' : 'Warung Epon'),
      // Default: the SaaS backend has the filter, pos-cashier does not (yet).
      salesDateFilter: dateFilter.isEmpty ? variant == AppVariant.saas : dateFilter == 'true',
    );
  }
}

class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Overridden in `main()` with the parsed build configuration.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
