enum FailureKind {
  /// No connection could be made (offline, DNS, refused).
  network,
  timeout,

  /// 401: the token is missing, revoked or invalid.
  unauthorized,

  /// 403: missing permission or plan module.
  forbidden,

  /// Tenant resolution failed (TENANT_* codes).
  tenant,
  notFound,

  /// 422: validation or business rule (stock, payment) rejected.
  validation,
  rateLimited,
  server,
  unknown,
}

/// The only error type that leaves the data layer. [message] is always
/// safe to show to a cashier (Indonesian, no stack traces).
class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.message, {
    this.code,
    this.statusCode,
    this.fieldErrors = const {},
    this.mayHaveReachedServer = false,
  });

  final FailureKind kind;
  final String message;

  /// Backend machine code, e.g. `TENANT_ACCESS_DENIED`, `PLAN_MODULE_UNAVAILABLE`.
  final String? code;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  /// True when the request may have been processed even though no response
  /// arrived (e.g. receive timeout). Writes must not be blindly re-sent.
  final bool mayHaveReachedServer;

  String? fieldError(String field) => fieldErrors[field]?.firstOrNull;

  @override
  String toString() => 'AppFailure($kind, $statusCode, $code): $message';
}
