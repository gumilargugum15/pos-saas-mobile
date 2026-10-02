import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/error_mapper.dart';
import '../../../data/repositories/auth_repository_impl.dart';
import '../../../data/repositories/tenant_repository_impl.dart';
import '../../../domain/entities/tenant.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/repositories/tenant_repository.dart';
import '../../../domain/usecases/cashier_access.dart';

enum SessionStatus {
  /// Checking the stored session (splash).
  initializing,

  /// The stored session could not be checked (e.g. offline). Retry or log out.
  startupError,
  unauthenticated,

  /// Logged in, more than one tenant and none chosen yet.
  selectingTenant,

  /// Logged in, but this user/tenant may not use the cashier app.
  accessDenied,

  /// Logged in, tenant active, access granted.
  ready,
}

class SessionState {
  const SessionState._(
    this.status, {
    this.user,
    this.tenants = const [],
    this.activeTenant,
    this.denialReason,
    this.message,
  });

  const SessionState.initializing() : this._(SessionStatus.initializing);

  const SessionState.startupError(String message) : this._(SessionStatus.startupError, message: message);

  const SessionState.unauthenticated({String? message}) : this._(SessionStatus.unauthenticated, message: message);

  const SessionState.selectingTenant(User user, List<Tenant> tenants, {Tenant? current, String? message})
      : this._(SessionStatus.selectingTenant, user: user, tenants: tenants, activeTenant: current, message: message);

  const SessionState.accessDenied(User user, List<Tenant> tenants, Tenant? tenant, AccessDenialReason reason)
      : this._(SessionStatus.accessDenied, user: user, tenants: tenants, activeTenant: tenant, denialReason: reason);

  const SessionState.ready(User user, List<Tenant> tenants, Tenant tenant)
      : this._(SessionStatus.ready, user: user, tenants: tenants, activeTenant: tenant);

  final SessionStatus status;
  final User? user;
  final List<Tenant> tenants;

  /// The tenant every request is scoped to (`X-Tenant-ID`). While selecting,
  /// it is the previously active tenant, if any.
  final Tenant? activeTenant;
  final AccessDenialReason? denialReason;

  /// A one-off notice for the current screen (e.g. "session expired").
  final String? message;

  bool get canSwitchTenant => tenants.length > 1;
}

/// Owns the session lifecycle: Splash → check session → tenant → access
/// check → app. Also reacts to session-level API events (401, tenant loss)
/// raised by any request anywhere in the app.
class SessionController extends Notifier<SessionState> {
  late AuthRepository _auth;
  late TenantRepository _tenants;

  /// Incremented whenever a flow starts or the session ends, so a slow
  /// response from an older flow can never overwrite a newer state.
  int _generation = 0;

  @override
  SessionState build() {
    _auth = ref.watch(authRepositoryProvider);
    _tenants = ref.watch(tenantRepositoryProvider);

    final subscription = ref.watch(apiClientProvider).events.listen(_onApiEvent);
    ref.onDispose(subscription.cancel);

    Future.microtask(restore);
    return const SessionState.initializing();
  }

  /// Restores the stored session, or lands on the login screen.
  Future<void> restore() async {
    final generation = ++_generation;
    state = const SessionState.initializing();

    if (!_auth.hasSession) {
      state = const SessionState.unauthenticated();
      return;
    }

    try {
      final user = await _auth.currentUser();
      if (generation != _generation) return;
      await _enter(user, generation);
    } on AppFailure catch (failure) {
      if (generation != _generation) return;
      if (failure.kind == FailureKind.unauthorized) {
        await _auth.clearLocalSession();
        state = const SessionState.unauthenticated(message: FailureMessages.unauthorized);
      } else {
        state = SessionState.startupError(failure.message);
      }
    }
  }

  /// Throws [AppFailure] (wrong credentials, inactive account, offline) so
  /// the login form can show it next to the fields.
  Future<void> login({required String email, required String password}) async {
    final generation = ++_generation;
    final user = await _auth.login(email: email, password: password);
    if (generation != _generation) return;

    try {
      await _enter(user, generation);
    } on AppFailure {
      // Logged in but the tenants could not be loaded: do not leave a
      // half-open session behind.
      await _auth.logout();
      rethrow;
    }
  }

  Future<void> selectTenant(Tenant tenant) async {
    final user = state.user;
    if (user == null) return;
    ++_generation;
    await _activate(user, state.tenants, tenant);
  }

  /// Opens the tenant picker with a fresh membership list.
  Future<void> switchTenant() async {
    final user = state.user;
    if (user == null) return;
    final generation = ++_generation;
    final tenants = await _tenants.fetchTenants();
    if (generation != _generation) return;
    state = SessionState.selectingTenant(user, tenants, current: state.activeTenant);
  }

  Future<void> logout() async {
    ++_generation;
    await _auth.logout();
    state = const SessionState.unauthenticated();
  }

  Future<void> _enter(User user, int generation) async {
    final tenants = await _tenants.fetchTenants();
    if (generation != _generation) return;

    if (tenants.isEmpty) {
      await _tenants.clearSelection();
      state = SessionState.accessDenied(user, tenants, null, AccessDenialReason.noTenant);
      return;
    }

    final storedId = _tenants.selectedTenantId;
    final selected = tenants.where((t) => t.id == storedId).firstOrNull ??
        (tenants.length == 1 ? tenants.single : null);

    if (selected == null) {
      if (storedId != null) await _tenants.clearSelection();
      state = SessionState.selectingTenant(user, tenants);
      return;
    }
    await _activate(user, tenants, selected);
  }

  Future<void> _activate(User user, List<Tenant> tenants, Tenant tenant) async {
    await _tenants.select(tenant.id);
    final denial = CashierAccess.evaluate(user, tenant);
    state = denial == null
        ? SessionState.ready(user, tenants, tenant)
        : SessionState.accessDenied(user, tenants, tenant, denial);
  }

  Future<void> _onApiEvent(ApiEvent event) async {
    switch (event) {
      case SessionExpired():
        if (state.status == SessionStatus.unauthenticated) return;
        ++_generation;
        await _auth.clearLocalSession();
        state = const SessionState.unauthenticated(message: FailureMessages.unauthorized);

      case TenantRejected():
        // Membership or tenant status changed on the server mid-session.
        final user = state.user;
        if (user == null ||
            (state.status != SessionStatus.ready && state.status != SessionStatus.accessDenied)) {
          return;
        }
        final generation = ++_generation;
        await _tenants.clearSelection();
        try {
          await _enter(user, generation);
        } on AppFailure catch (failure) {
          if (generation == _generation) state = SessionState.startupError(failure.message);
        }
    }
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The active tenant, for features that must reset when it changes
/// (cart, caches): `ref.watch(activeTenantProvider)`.
final activeTenantProvider = Provider<Tenant?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.status == SessionStatus.ready ? session.activeTenant : null;
});

final currentUserProvider = Provider<User?>((ref) => ref.watch(sessionControllerProvider.select((s) => s.user)));

final cashierCapabilitiesProvider = Provider<CashierCapabilities?>((ref) {
  final user = ref.watch(currentUserProvider);
  return user == null ? null : CashierCapabilities(user);
});
