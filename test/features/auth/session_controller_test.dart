import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/error/app_failure.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/data/repositories/tenant_repository_impl.dart';
import 'package:kagoem_pos_mobile/domain/usecases/cashier_access.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

/// Waits until the session leaves the transient states.
Future<SessionState> settle(ProviderContainer container) async {
  final completer = Completer<SessionState>();
  bool done(SessionState s) => s.status != SessionStatus.initializing;
  final sub = container.listen(sessionControllerProvider, (_, next) {
    if (done(next) && !completer.isCompleted) completer.complete(next);
  }, fireImmediately: true);
  final state = await completer.future.timeout(const Duration(seconds: 5));
  sub.close();
  return state;
}

Future<SessionState> waitFor(
  ProviderContainer container,
  SessionStatus status, {
  bool Function(SessionState)? where,
}) async {
  final completer = Completer<SessionState>();
  final sub = container.listen(sessionControllerProvider, (_, next) {
    if (next.status == status && (where?.call(next) ?? true) && !completer.isCompleted) completer.complete(next);
  }, fireImmediately: true);
  final state = await completer.future.timeout(const Duration(seconds: 5));
  sub.close();
  return state;
}

void main() {
  late TestHarness h;
  late ProviderContainer container;

  setUp(() {
    h = TestHarness();
    container = h.container();
  });

  tearDown(() => container.dispose());

  SessionController controller() => container.read(sessionControllerProvider.notifier);

  void backendWith({List<Map<String, dynamic>>? tenants, Map<String, dynamic>? user}) {
    final u = user ?? userJson();
    h.backend.reply('POST', '/auth/login', 200, ok({'user': u, 'token': '5|tok'}, message: 'Login berhasil'));
    h.backend.reply('GET', '/auth/me', 200, ok(u));
    h.backend.reply('GET', '/tenants', 200, ok(tenants ?? [tenantJson()]));
    h.backend.reply('POST', '/auth/logout', 200, ok(null));
  }

  group('startup', () {
    test('no stored token → login screen', () async {
      final state = await settle(container);
      expect(state.status, SessionStatus.unauthenticated);
      expect(h.backend.requests, isEmpty);
    });

    test('stored token + stored tenant → ready without a picker', () async {
      backendWith(tenants: [tenantJson(id: 1), tenantJson(id: 2, name: 'Toko XYZ')]);
      await h.session.saveToken('5|tok');
      await h.session.saveTenantId(2);

      final state = await settle(container);
      expect(state.status, SessionStatus.ready);
      expect(state.activeTenant?.name, 'Toko XYZ');
      expect(state.user?.name, 'Siti Kasir');
    });

    test('token expired (401 on /auth/me) → login with notice, token wiped', () async {
      h.backend.reply('GET', '/auth/me', 401, {'success': false, 'message': 'Unauthenticated.', 'errors': []});
      await h.session.saveToken('5|old');

      final state = await settle(container);
      expect(state.status, SessionStatus.unauthenticated);
      expect(state.message, contains('Sesi Anda telah berakhir'));
      expect(h.session.hasToken, isFalse);
      expect(h.store.values, isEmpty);
    });

    test('offline at startup → retryable error, session kept', () async {
      h.backend.failures['GET /auth/me'] = DioExceptionType.connectionError;
      await h.session.saveToken('5|tok');

      final state = await settle(container);
      expect(state.status, SessionStatus.startupError);
      expect(h.session.hasToken, isTrue);

      h.backend.failures.clear();
      backendWith();
      await controller().restore();
      expect(container.read(sessionControllerProvider).status, SessionStatus.ready);
    });
  });

  group('login', () {
    setUp(() async => settle(container));

    test('success with one tenant → token stored securely, tenant auto-selected, ready', () async {
      backendWith();
      await controller().login(email: ' siti@toko.id ', password: 'rahasia');

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.ready);
      expect(h.store.values['kagoem.session.token'], '5|tok');
      expect(h.store.values['kagoem.session.tenant_id'], '1');
      expect(h.store.values.values, isNot(contains('rahasia')));

      final login = h.backend.calls('POST', '/auth/login').single;
      expect(login.data, {'email': 'siti@toko.id', 'password': 'rahasia'});
      // Requests after login carry the token and tenant.
      expect(h.backend.calls('GET', '/tenants').single.headers['Authorization'], 'Bearer 5|tok');
    });

    test('wrong password → AppFailure with the backend message, no token', () async {
      h.backend.reply('POST', '/auth/login', 422, validationError({
        'email': ['Email atau password salah.'],
      }));

      await expectLater(
        controller().login(email: 'siti@toko.id', password: 'x'),
        throwsA(isA<AppFailure>().having((f) => f.message, 'message', 'Email atau password salah.')),
      );
      expect(container.read(sessionControllerProvider).status, SessionStatus.unauthenticated);
      expect(h.session.hasToken, isFalse);
    });

    test('several tenants → picker, then selecting one → ready', () async {
      backendWith(tenants: [tenantJson(id: 1), tenantJson(id: 2, name: 'Toko XYZ')]);
      await controller().login(email: 'siti@toko.id', password: 'p');
      expect(container.read(sessionControllerProvider).status, SessionStatus.selectingTenant);

      final xyz = container.read(sessionControllerProvider).tenants.last;
      await controller().selectTenant(xyz);

      expect(container.read(sessionControllerProvider).status, SessionStatus.ready);
      expect(container.read(activeTenantProvider)?.id, 2);
      expect(container.read(tenantRepositoryProvider).selectedTenantId, 2);
    });

    test('user without manage-sales → access denied', () async {
      backendWith(user: userJson(roles: ['Gudang'], permissions: ['manage-inventory']));
      await controller().login(email: 'g@toko.id', password: 'p');

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.accessDenied);
      expect(state.denialReason, AccessDenialReason.missingPermission);
      expect(container.read(activeTenantProvider), isNull);
    });

    test('tenant plan without sales → access denied', () async {
      backendWith(tenants: [tenantJson(modules: ['products'])]);
      await controller().login(email: 'siti@toko.id', password: 'p');
      expect(container.read(sessionControllerProvider).denialReason, AccessDenialReason.moduleUnavailable);
    });

    test('no tenant membership → access denied', () async {
      backendWith(tenants: []);
      await controller().login(email: 'siti@toko.id', password: 'p');
      expect(container.read(sessionControllerProvider).denialReason, AccessDenialReason.noTenant);
    });

    test('tenants cannot be loaded → login fails and no half-open session remains', () async {
      backendWith();
      h.backend.failures['GET /tenants'] = DioExceptionType.connectionError;

      await expectLater(controller().login(email: 'siti@toko.id', password: 'p'), throwsA(isA<AppFailure>()));
      expect(h.session.hasToken, isFalse);
      expect(h.backend.calls('POST', '/auth/logout'), isNotEmpty);
    });
  });

  group('running session', () {
    setUp(() async {
      backendWith(tenants: [tenantJson(id: 1), tenantJson(id: 2, name: 'Toko XYZ')]);
      await h.session.saveToken('5|tok');
      await h.session.saveTenantId(1);
      await settle(container);
    });

    test('logout revokes the token and wipes the device session', () async {
      await controller().logout();
      expect(container.read(sessionControllerProvider).status, SessionStatus.unauthenticated);
      expect(h.backend.calls('POST', '/auth/logout').single.headers['Authorization'], 'Bearer 5|tok');
      expect(h.store.values, isEmpty);
    });

    test('logout still clears the device when the server is unreachable', () async {
      h.backend.failures['POST /auth/logout'] = DioExceptionType.connectionError;
      await controller().logout();
      expect(container.read(sessionControllerProvider).status, SessionStatus.unauthenticated);
      expect(h.store.values, isEmpty);
    });

    test('a 401 from any feature request ends the session', () async {
      h.backend.reply('GET', '/products', 401, {'success': false, 'message': 'Unauthenticated.', 'errors': []});

      await expectLater(
        container.read(apiClientProvider).get('/products', parse: (d) => d),
        throwsA(isA<AppFailure>()),
      );
      final state = await waitFor(container, SessionStatus.unauthenticated);
      expect(state.message, contains('Sesi Anda telah berakhir'));
      expect(h.store.values, isEmpty);
    });

    test('losing tenant membership mid-session re-resolves the tenant', () async {
      h.backend.reply('GET', '/products', 403, {
        'success': false,
        'message': 'Keanggotaan Anda pada tenant ini tidak aktif.',
        'code': 'TENANT_MEMBERSHIP_INACTIVE',
        'errors': [],
      });
      // The server now only lists the other tenant.
      h.backend.reply('GET', '/tenants', 200, ok([tenantJson(id: 2, name: 'Toko XYZ')]));

      await expectLater(
        container.read(apiClientProvider).get('/products', parse: (d) => d),
        throwsA(isA<AppFailure>()),
      );
      await waitFor(container, SessionStatus.ready, where: (s) => s.activeTenant?.id == 2);
      expect(h.session.tenantId, 2);
    });

    test('switching tenant opens the picker and keeps the current one for "back"', () async {
      await controller().switchTenant();
      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.selectingTenant);
      expect(state.activeTenant?.id, 1);
      expect(container.read(activeTenantProvider), isNull);
    });
  });
}
