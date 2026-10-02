import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppEnvironment { development, staging, production }

/// Build-time configuration, injected with
/// `--dart-define-from-file=env/<environment>.json` (see README).
class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  final AppEnvironment environment;

  /// Includes the API version prefix, e.g. `https://pos.example.com/api/v1`.
  final String apiBaseUrl;

  bool get isProduction => environment == AppEnvironment.production;

  /// Throws [ConfigException] when the build was made without a valid
  /// environment file, so a misconfigured build fails loudly at startup
  /// instead of calling a wrong server.
  factory AppConfig.fromEnvironment() {
    const envName = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const baseUrl = String.fromEnvironment('API_BASE_URL');

    return AppConfig.parse(envName: envName, baseUrl: baseUrl);
  }

  factory AppConfig.parse({required String envName, required String baseUrl}) {
    final environment = AppEnvironment.values
        .where((e) => e.name == envName)
        .firstOrNull;
    if (environment == null) {
      throw ConfigException('APP_ENV tidak dikenal: "$envName".');
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

    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return AppConfig(environment: environment, apiBaseUrl: normalized);
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
