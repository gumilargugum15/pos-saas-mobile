import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/error/app_failure.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';

import '../../helpers/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late SessionStore session;
  late ApiClient api;

  setUp(() {
    backend = FakeBackend();
    session = SessionStore(InMemoryKeyValueStore());
    api = ApiClient(
      baseUrl: 'http://pos.test/api/v1',
      session: session,
      adapter: backend,
      retryDelay: Duration.zero,
    );
  });

  tearDown(() => api.dispose());

  test('sends Accept, Bearer token and X-Tenant-ID', () async {
    await session.saveToken('1|secret');
    await session.saveTenantId(4);
    backend.reply('GET', '/ping', 200, ok('pong'));

    await api.get('/ping', parse: (d) => d);

    final headers = backend.requests.single.headers;
    expect(headers['Accept'], 'application/json');
    expect(headers['Authorization'], 'Bearer 1|secret');
    expect(headers['X-Tenant-ID'], '4');
    expect(backend.requests.single.uri.toString(), 'http://pos.test/api/v1/ping');
  });

  test('omits auth headers when there is no session', () async {
    backend.reply('GET', '/ping', 200, ok('pong'));
    await api.get('/ping', parse: (d) => d);
    final headers = backend.requests.single.headers;
    expect(headers.containsKey('Authorization'), isFalse);
    expect(headers.containsKey('X-Tenant-ID'), isFalse);
  });

  test('parses the success envelope and status code', () async {
    backend.reply('POST', '/things', 201, ok({'id': 9}, message: 'Dibuat'));
    final response = await api.post('/things', body: {}, parse: (d) => (d as Map)['id']);
    expect(response.data, 9);
    expect(response.message, 'Dibuat');
    expect(response.statusCode, 201);
  });

  test('parses a paginated envelope and drops null query values', () async {
    backend.reply('GET', '/products', 200, ok(
      [
        {'id': 1},
        {'id': 2},
      ],
      meta: {'current_page': 1, 'last_page': 3, 'per_page': 2, 'total': 6},
    ));

    final page = await api.getPage('/products', query: {'search': null, 'is_active': 1}, parseItem: (j) => j['id']);

    expect(page.items, [1, 2]);
    expect(page.meta.total, 6);
    expect(page.meta.hasMore, isTrue);
    expect(backend.requests.single.uri.queryParameters, {'is_active': '1'});
  });

  test('401 throws and emits SessionExpired', () async {
    backend.reply('GET', '/auth/me', 401, {'success': false, 'message': 'Unauthenticated.', 'errors': []});
    final events = <ApiEvent>[];
    final sub = api.events.listen(events.add);

    await expectLater(
      api.get('/auth/me', parse: (d) => d),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.unauthorized)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.single, isA<SessionExpired>());
    await sub.cancel();
  });

  test('tenant error emits TenantRejected with the code', () async {
    backend.reply('GET', '/products', 403, {
      'success': false,
      'message': 'Keanggotaan Anda pada tenant ini tidak aktif.',
      'code': 'TENANT_MEMBERSHIP_INACTIVE',
      'errors': [],
    });
    final events = <ApiEvent>[];
    final sub = api.events.listen(events.add);

    await expectLater(api.get('/products', parse: (d) => d), throwsA(isA<AppFailure>()));
    await Future<void>.delayed(Duration.zero);
    expect((events.single as TenantRejected).code, 'TENANT_MEMBERSHIP_INACTIVE');
    await sub.cancel();
  });

  test('GET is retried once on a network error', () async {
    var attempts = 0;
    backend.on('GET', '/ping', (_) {
      attempts++;
      return (status: 200, body: ok('pong'));
    });
    backend.failures['GET /ping'] = DioExceptionType.connectionError;

    await expectLater(api.get('/ping', parse: (d) => d), throwsA(isA<AppFailure>()));
    expect(backend.calls('GET', '/ping').length, 2);
    expect(attempts, 0);
  });

  test('POST is never retried automatically', () async {
    backend.failures['POST /sales'] = DioExceptionType.receiveTimeout;

    await expectLater(
      api.post('/sales', body: {}, parse: (d) => d),
      throwsA(isA<AppFailure>().having((f) => f.mayHaveReachedServer, 'mayHaveReachedServer', isTrue)),
    );
    expect(backend.calls('POST', '/sales').length, 1);
  });

  test('a response without the envelope is a server failure', () async {
    backend.reply('GET', '/odd', 200, {'unexpected': true});
    await expectLater(
      api.get('/odd', parse: (d) => d),
      throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
    );
  });
}
