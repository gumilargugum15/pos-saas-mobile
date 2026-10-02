import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._session);

  final AuthRemoteDataSource _remote;
  final SessionStore _session;

  @override
  bool get hasSession => _session.hasToken;

  @override
  Future<User> login({required String email, required String password}) async {
    final result = await _remote.login(email.trim(), password);
    if (result.token.isEmpty) {
      throw const AppFailure(FailureKind.server, 'Server tidak mengirim token login.');
    }
    await _session.saveToken(result.token);
    return result.user;
  }

  @override
  Future<User> currentUser() => _remote.me();

  @override
  Future<void> logout() async {
    try {
      await _remote.logout();
    } on AppFailure catch (e) {
      // The local session is cleared regardless; an unreachable server must
      // not keep the cashier logged in on this device.
      debugPrint('Logout request failed: $e');
    } finally {
      await _session.clear();
    }
  }

  @override
  Future<void> clearLocalSession() => _session.clear();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    AuthRemoteDataSource(ref.watch(apiClientProvider)),
    ref.watch(sessionStoreProvider),
  );
});
