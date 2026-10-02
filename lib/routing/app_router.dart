import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/barcode/presentation/scanner_page.dart';
import '../features/auth/presentation/access_denied_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/dashboard/presentation/home_page.dart';
import '../features/pos/presentation/pos_page.dart';
import '../features/products/presentation/products_page.dart';
import '../features/tenant/presentation/tenant_picker_page.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const tenant = '/tenant';
  static const denied = '/denied';
  static const home = '/';
  static const pos = '/pos';
  static const products = '/products';

  /// Screens owned by the session flow; a ready session never stays on them.
  static const gates = {splash, login, tenant, denied};
}

/// Where the session state says the user must be, or null to stay.
/// Kept pure so it can be unit tested.
@visibleForTesting
String? sessionRedirect(SessionStatus status, String location) {
  final target = switch (status) {
    SessionStatus.initializing || SessionStatus.startupError => Routes.splash,
    SessionStatus.unauthenticated => Routes.login,
    SessionStatus.selectingTenant => Routes.tenant,
    SessionStatus.accessDenied => Routes.denied,
    SessionStatus.ready => Routes.gates.contains(location) ? Routes.home : null,
  };
  return target == location ? null : target;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<SessionStatus>(ref.read(sessionControllerProvider).status);
  ref.listen(sessionControllerProvider.select((s) => s.status), (_, status) => refresh.value = status);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => sessionRedirect(refresh.value, state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: Routes.tenant, builder: (_, _) => const TenantPickerPage()),
      GoRoute(path: Routes.denied, builder: (_, _) => const AccessDeniedPage()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
      GoRoute(
        path: Routes.pos,
        builder: (_, _) => const PosPage(),
        routes: [
          GoRoute(path: 'cart', builder: (_, _) => const CartPage()),
          GoRoute(path: 'scan', builder: (_, _) => const ScannerPage()),
        ],
      ),
      GoRoute(path: Routes.products, builder: (_, _) => const ProductsPage()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
