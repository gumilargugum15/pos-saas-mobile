import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key/value contract so the session can be tested without the
/// platform keystore.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Session values kept in the platform secure storage (Android Keystore /
/// iOS Keychain) and mirrored in memory, because the API client reads them
/// on every request. The password is never stored.
class SessionStore {
  SessionStore(this._store);

  static const _tokenKey = 'kagoem.session.token';
  static const _tenantKey = 'kagoem.session.tenant_id';
  static const _branchKey = 'kagoem.session.branch_id';

  final SecureKeyValueStore _store;

  String? _token;
  int? _tenantId;
  int? _branchId;

  String? get token => _token;
  int? get tenantId => _tenantId;
  int? get branchId => _branchId;
  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Reads the persisted session. A keystore that can no longer decrypt its
  /// data (e.g. restored onto another device) is wiped instead of crashing
  /// the app: the cashier simply logs in again.
  Future<void> load() async {
    try {
      _token = await _store.read(_tokenKey);
      _tenantId = int.tryParse(await _store.read(_tenantKey) ?? '');
      _branchId = int.tryParse(await _store.read(_branchKey) ?? '');
    } catch (e) {
      debugPrint('SessionStore.load failed, clearing session: $e');
      await clear();
    }
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _store.write(_tokenKey, token);
  }

  /// Switching tenant always forgets the branch: branches belong to a tenant.
  Future<void> saveTenantId(int? tenantId) async {
    if (tenantId != _tenantId) await saveBranchId(null);
    _tenantId = tenantId;
    await _writeOrDelete(_tenantKey, tenantId?.toString());
  }

  Future<void> saveBranchId(int? branchId) async {
    _branchId = branchId;
    await _writeOrDelete(_branchKey, branchId?.toString());
  }

  Future<void> clear() async {
    _token = null;
    _tenantId = null;
    _branchId = null;
    for (final key in [_tokenKey, _tenantKey, _branchKey]) {
      try {
        await _store.delete(key);
      } catch (e) {
        debugPrint('SessionStore.clear failed for $key: $e');
      }
    }
  }

  Future<void> _writeOrDelete(String key, String? value) =>
      value == null ? _store.delete(key) : _store.write(key, value);
}

/// Overridden in `main()` with an already loaded store.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => throw UnimplementedError('sessionStoreProvider must be overridden'),
);
