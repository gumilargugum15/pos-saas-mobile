import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../error/app_failure.dart';
import '../storage/session_store.dart';
import 'api_response.dart';
import 'error_mapper.dart';

/// Session-level signals raised by any request, consumed by the session
/// controller (so features never handle 401 / tenant loss themselves).
sealed class ApiEvent {
  const ApiEvent();
}

class SessionExpired extends ApiEvent {
  const SessionExpired();
}

class TenantRejected extends ApiEvent {
  const TenantRejected(this.code);

  final String? code;
}

typedef JsonParser<T> = T Function(Object? data);

/// The single HTTP entry point. Every call returns parsed data or throws an
/// [AppFailure]; Dio types never leave this class.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required SessionStore session,
    HttpClientAdapter? adapter,
    this._retryDelay = const Duration(milliseconds: 600),
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        contentType: Headers.jsonContentType,
        // Without it Laravel may answer auth errors with an HTML redirect.
        headers: {Headers.acceptHeader: Headers.jsonContentType},
      ),
    );
    _dio.interceptors.add(SessionHeadersInterceptor(session));
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  late final Dio _dio;
  final Duration _retryDelay;
  final _events = StreamController<ApiEvent>.broadcast();

  Stream<ApiEvent> get events => _events.stream;

  /// GETs are idempotent, so one automatic retry is made on network errors.
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required JsonParser<T> parse,
  }) async {
    try {
      return await _send('GET', path, query: query, parse: parse);
    } on AppFailure catch (f) {
      if (f.kind != FailureKind.network && f.kind != FailureKind.timeout) rethrow;
      await Future<void>.delayed(_retryDelay);
      return _send('GET', path, query: query, parse: parse);
    }
  }

  Future<Paginated<T>> getPage<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic> json) parseItem,
  }) async {
    final response = await get<List<T>>(
      path,
      query: query,
      parse: (data) => [for (final item in data as List) parseItem(item as Map<String, dynamic>)],
    );
    final meta = response.meta ??
        PageMeta(currentPage: 1, lastPage: 1, perPage: response.data.length, total: response.data.length);
    return Paginated(items: response.data, meta: meta);
  }

  /// Writes are never retried automatically: a lost response does not mean
  /// the server did nothing (see [AppFailure.mayHaveReachedServer]).
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? body,
    Map<String, String>? headers,
    required JsonParser<T> parse,
  }) =>
      _send('POST', path, body: body, headers: headers, parse: parse);

  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? body,
    required JsonParser<T> parse,
  }) =>
      _send('PUT', path, body: body, parse: parse);

  Future<ApiResponse<T>> _send<T>(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? headers,
    required JsonParser<T> parse,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query == null ? null : _withoutNulls(query),
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      final failure = mapDioException(e);
      _emitFor(failure);
      throw failure;
    }

    final envelope = response.data;
    if (envelope is! Map || !envelope.containsKey('data')) {
      throw const AppFailure(FailureKind.server, 'Respons server tidak valid.');
    }
    try {
      final meta = envelope['meta'];
      return ApiResponse(
        data: parse(envelope['data']),
        message: envelope['message'] as String? ?? '',
        statusCode: response.statusCode ?? 200,
        meta: meta is Map<String, dynamic> ? PageMeta.fromJson(meta) : null,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(FailureKind.server, 'Respons server tidak sesuai format yang diharapkan.');
    }
  }

  void _emitFor(AppFailure failure) {
    if (failure.kind == FailureKind.unauthorized) {
      _events.add(const SessionExpired());
    } else if (failure.kind == FailureKind.tenant) {
      _events.add(TenantRejected(failure.code));
    }
  }

  static Map<String, dynamic> _withoutNulls(Map<String, dynamic> query) =>
      {for (final e in query.entries) if (e.value != null && e.value != '') e.key: e.value};

  void dispose() {
    _events.close();
    _dio.close(force: true);
  }
}

/// Adds the Sanctum bearer token and the active tenant (`X-Tenant-ID`,
/// read by the backend's TenantMiddleware) to every request.
class SessionHeadersInterceptor extends Interceptor {
  SessionHeadersInterceptor(this._session);

  final SessionStore _session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _session.token;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    final tenantId = _session.tenantId;
    if (tenantId != null) {
      options.headers['X-Tenant-ID'] = tenantId.toString();
    }
    handler.next(options);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    session: ref.watch(sessionStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});
