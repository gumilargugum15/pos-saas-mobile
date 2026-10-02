import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/routing/app_router.dart';

void main() {
  test('each session status pins its gate screen', () {
    expect(sessionRedirect(SessionStatus.initializing, '/'), '/splash');
    expect(sessionRedirect(SessionStatus.startupError, '/'), '/splash');
    expect(sessionRedirect(SessionStatus.unauthenticated, '/'), '/login');
    expect(sessionRedirect(SessionStatus.selectingTenant, '/'), '/tenant');
    expect(sessionRedirect(SessionStatus.accessDenied, '/'), '/denied');
  });

  test('no redirect loop when already on the target', () {
    expect(sessionRedirect(SessionStatus.unauthenticated, '/login'), isNull);
    expect(sessionRedirect(SessionStatus.accessDenied, '/denied'), isNull);
  });

  test('a ready session leaves gate screens and keeps app routes', () {
    for (final gate in Routes.gates) {
      expect(sessionRedirect(SessionStatus.ready, gate), '/');
    }
    expect(sessionRedirect(SessionStatus.ready, '/'), isNull);
    expect(sessionRedirect(SessionStatus.ready, '/transactions'), isNull);
  });

  test('a signed-out user can never reach app routes', () {
    expect(sessionRedirect(SessionStatus.unauthenticated, '/transactions'), '/login');
  });
}
