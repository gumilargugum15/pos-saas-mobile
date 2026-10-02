import '../entities/user.dart';

/// Every method throws `AppFailure` on error.
abstract interface class AuthRepository {
  /// Whether a token is stored on this device.
  bool get hasSession;

  /// Logs in and persists the token securely.
  Future<User> login({required String email, required String password});

  /// The user behind the stored token (`GET /auth/me`).
  Future<User> currentUser();

  /// Revokes the token on the server (best effort) and always clears the
  /// local session.
  Future<void> logout();

  /// Clears the local session only (the server already rejected the token).
  Future<void> clearLocalSession();
}
