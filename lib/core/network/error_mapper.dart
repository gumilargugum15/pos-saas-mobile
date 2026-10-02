import 'package:dio/dio.dart';

import '../error/app_failure.dart';

/// Backend codes from `TenantResolutionException` (backend/app/Tenancy).
const tenantErrorCodes = {
  'TENANT_REQUIRED',
  'TENANT_NOT_FOUND',
  'TENANT_INACTIVE',
  'TENANT_ACCESS_DENIED',
  'TENANT_MEMBERSHIP_INACTIVE',
};

abstract final class FailureMessages {
  static const network = 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
  static const timeout = 'Server terlalu lama merespons. Silakan coba lagi.';
  static const unauthorized = 'Sesi Anda telah berakhir. Silakan login kembali.';
  static const forbidden = 'Anda tidak memiliki akses untuk fitur ini.';
  static const notFound = 'Data tidak ditemukan.';
  static const validation = 'Data tidak valid. Periksa kembali isian Anda.';
  static const rateLimited = 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
  static const server = 'Terjadi kesalahan pada server. Silakan coba lagi.';
  static const unknown = 'Terjadi kesalahan. Silakan coba lagi.';
}

AppFailure mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
      return const AppFailure(FailureKind.timeout, FailureMessages.timeout);
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const AppFailure(
        FailureKind.timeout,
        FailureMessages.timeout,
        mayHaveReachedServer: true,
      );
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return const AppFailure(FailureKind.network, FailureMessages.network);
    case DioExceptionType.badResponse:
      final response = e.response;
      return mapErrorResponse(response?.statusCode ?? 0, response?.data);
    case DioExceptionType.cancel:
      return const AppFailure(FailureKind.unknown, 'Permintaan dibatalkan.');
    case DioExceptionType.unknown:
      // Usually a socket error; whether the request was sent is unknown.
      return const AppFailure(
        FailureKind.network,
        FailureMessages.network,
        mayHaveReachedServer: true,
      );
  }
}

/// Maps the backend error envelope `{success:false, message, code?, errors}`
/// (backend/bootstrap/app.php) to a cashier-friendly failure.
AppFailure mapErrorResponse(int status, Object? body) {
  final json = body is Map ? body : const {};
  final backendMessage = json['message'] is String ? json['message'] as String : null;
  final code = json['code'] is String ? json['code'] as String : null;
  final fieldErrors = _parseFieldErrors(json['errors']);

  if (status == 401) {
    return AppFailure(FailureKind.unauthorized, FailureMessages.unauthorized, statusCode: status);
  }

  if (code != null && tenantErrorCodes.contains(code)) {
    return AppFailure(
      FailureKind.tenant,
      backendMessage ?? FailureMessages.forbidden,
      code: code,
      statusCode: status,
    );
  }

  switch (status) {
    case 403:
      // PLAN_MODULE_UNAVAILABLE carries an Indonesian, user-facing message;
      // the generic `can:` denial is Laravel's English default.
      final message = code != null && backendMessage != null ? backendMessage : FailureMessages.forbidden;
      return AppFailure(FailureKind.forbidden, message, code: code, statusCode: status);
    case 404:
      return AppFailure(FailureKind.notFound, FailureMessages.notFound, statusCode: status);
    case 409:
      return AppFailure(FailureKind.unknown, backendMessage ?? FailureMessages.unknown, code: code, statusCode: status);
    case 422:
      return AppFailure(
        FailureKind.validation,
        _validationMessage(backendMessage, fieldErrors),
        code: code,
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    case 429:
      return AppFailure(FailureKind.rateLimited, FailureMessages.rateLimited, statusCode: status);
  }

  if (status >= 500) {
    return AppFailure(FailureKind.server, FailureMessages.server, statusCode: status);
  }
  return AppFailure(FailureKind.unknown, FailureMessages.unknown, statusCode: status);
}

/// Business rules (stock, payment, login) answer in Indonesian and are shown
/// as-is. Laravel's built-in rule messages are English (APP_LOCALE=en) and
/// name raw fields, so they are replaced by a generic message.
String _validationMessage(String? backendMessage, Map<String, List<String>> fieldErrors) {
  final first = fieldErrors.values.expand((m) => m).firstOrNull;
  if (first != null && !_isFrameworkMessage(first)) return first;
  if (backendMessage != null && backendMessage != 'Validasi Gagal' && !_isFrameworkMessage(backendMessage)) {
    return backendMessage;
  }
  return FailureMessages.validation;
}

bool _isFrameworkMessage(String message) =>
    message.startsWith('The ') || message.startsWith('validation.');

Map<String, List<String>> _parseFieldErrors(Object? errors) {
  if (errors is! Map) return const {};
  return {
    for (final entry in errors.entries)
      if (entry.value is List)
        entry.key.toString(): [for (final m in entry.value as List) m.toString()],
  };
}
