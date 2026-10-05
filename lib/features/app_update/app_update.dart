import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_failure.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../receipt/receipt_providers.dart';

/// This build's version (`version:` in pubspec.yaml, passed by Flutter as
/// FLUTTER_BUILD_NAME). Empty in tests and unusual builds: no update check.
const appVersion = String.fromEnvironment('FLUTTER_BUILD_NAME');

/// [appVersion] as a provider, so tests can pretend to be a given build.
final currentAppVersionProvider = Provider<String>((ref) => appVersion);

/// Compares dotted versions numerically ("1.10.0" > "1.9.2"). Build
/// metadata after "+" or "-" is ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      [for (final p in v.split(RegExp(r'[+-]')).first.split('.')) int.tryParse(p.trim()) ?? 0];
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// A published Android release (`GET /mobile-app/android`,
/// kagoem-pos-saas MobileAppController).
class AppRelease {
  const AppRelease({required this.version, required this.downloadUrl, this.sizeBytes});

  final String version;
  final Uri downloadUrl;
  final int? sizeBytes;

  String? get sizeLabel => sizeBytes == null ? null : '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The release, if one is published and newer than this build; otherwise
/// null. Never throws: an update check must not disturb the till.
///
/// The download link is only trusted on the API's own scheme and host
/// (https in staging/production, which AppConfig enforces), so a tampered
/// response cannot point the cashier to another APK.
Future<AppRelease?> fetchNewerRelease(ApiClient api, {required String currentVersion, required String apiBaseUrl}) async {
  if (currentVersion.isEmpty) return null;
  try {
    final response = await api.get('/mobile-app/android', parse: Json.asMap);
    final data = response.data;
    if (!Json.asBool(data['available'])) return null;
    final version = Json.asStringOrNull(data['version'])?.trim() ?? '';
    final url = Uri.tryParse(Json.asString(data['download_url']));
    final apiUri = Uri.parse(apiBaseUrl);
    if (version.isEmpty || url == null) return null;
    if (url.scheme != apiUri.scheme || url.host != apiUri.host) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;
    return AppRelease(version: version, downloadUrl: url, sizeBytes: Json.asIntOrNull(data['size']));
  } on AppFailure catch (f) {
    // 404 = this backend has no distribution endpoint (e.g. pos-cashier).
    debugPrint('Update check skipped: ${f.kind}');
    return null;
  }
}

/// Checked once per app launch (kept alive).
final availableUpdateProvider = FutureProvider<AppRelease?>((ref) {
  final config = ref.watch(appConfigProvider);
  return fetchNewerRelease(
    ref.watch(apiClientProvider),
    currentVersion: ref.watch(currentAppVersionProvider),
    apiBaseUrl: config.apiBaseUrl,
  );
});

/// Releases the user chose "Nanti" for; remembered on the device so the
/// banner returns only for an even newer version.
class DismissedUpdateController extends AsyncNotifier<String?> {
  static const _key = 'kagoem.update.dismissed_version';

  @override
  Future<String?> build() => ref.watch(deviceStoreProvider).read(_key);

  Future<void> dismiss(String version) async {
    await ref.read(deviceStoreProvider).write(_key, version);
    state = AsyncData(version);
  }
}

final dismissedUpdateProvider =
    AsyncNotifierProvider<DismissedUpdateController, String?>(DismissedUpdateController.new);

/// The release to advertise now, or null.
final updateToShowProvider = Provider<AppRelease?>((ref) {
  final release = ref.watch(availableUpdateProvider).value;
  final dismissed = ref.watch(dismissedUpdateProvider);
  if (release == null || dismissed.isLoading) return null;
  final skipped = dismissed.value;
  if (skipped != null && compareVersions(release.version, skipped) <= 0) return null;
  return release;
});
