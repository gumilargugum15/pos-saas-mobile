import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';

typedef FakeReply = ({int status, Object? body});
typedef FakeHandler = FakeReply Function(RequestOptions request);

/// In-memory stand-in for the Laravel API, plugged into Dio as its
/// [HttpClientAdapter]. Routes are keyed by `'METHOD /path'`.
class FakeBackend implements HttpClientAdapter {
  final Map<String, FakeHandler> routes = {};
  final List<RequestOptions> requests = [];

  /// When set for a route key, the request fails with this Dio error type.
  final Map<String, DioExceptionType> failures = {};

  void on(String method, String path, FakeHandler handler) => routes['$method $path'] = handler;

  void reply(String method, String path, int status, Object? body) =>
      on(method, path, (_) => (status: status, body: body));

  Iterable<RequestOptions> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.uri.path.endsWith(path));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final path = options.uri.path.replaceFirst(RegExp(r'^/api/v1'), '');
    final key = '${options.method} $path';

    final failure = failures[key];
    if (failure != null) throw DioException(requestOptions: options, type: failure);

    final handler = routes[key];
    final reply = handler?.call(options) ??
        (status: 404, body: {'success': false, 'message': 'Not found', 'errors': <String, dynamic>{}});
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class InMemoryKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Map<String, dynamic> ok(Object? data, {String message = 'Berhasil', Map<String, dynamic>? meta}) => {
      'success': true,
      'message': message,
      'data': data,
      'meta': ?meta,
    };

Map<String, dynamic> userJson({
  int id = 7,
  String name = 'Siti Kasir',
  List<String> roles = const ['Kasir'],
  List<String> permissions = const ['manage-sales', 'operate-cash-drawer'],
  int? branchId = 3,
}) =>
    {
      'id': id,
      'name': name,
      'email': 'siti@toko.id',
      'phone': null,
      'avatar_url': null,
      'is_active': true,
      'branch_id': branchId,
      'branch_name': branchId == null ? null : 'Toko Pusat',
      'roles': roles,
      'permissions': permissions,
    };

Map<String, dynamic> tenantJson({int id = 1, String name = 'Toko ABC', List<String>? modules}) => {
      'id': id,
      'name': name,
      'slug': name.toLowerCase().replaceAll(' ', '-'),
      'status': 'active',
      'role': 'Kasir',
      'membership_status': 'active',
      'plan': 'business',
      'limits': {'max_users': 5, 'max_branches': 3, 'max_products': 500},
      'modules': modules,
    };

Map<String, dynamic> validationError(Map<String, List<String>> errors) =>
    {'success': false, 'message': 'Validasi Gagal', 'errors': errors};
