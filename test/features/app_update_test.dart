import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';
import 'package:kagoem_pos_mobile/features/app_update/app_update.dart';
import 'package:kagoem_pos_mobile/features/app_update/update_widgets.dart';

import '../helpers/fake_backend.dart';
import '../helpers/test_app.dart';

Map<String, dynamic> release({String version = '1.4.0', String? url, bool available = true}) => ok({
      'available': available,
      'version': version,
      'size': 27610881,
      'updated_at': '2026-10-05T01:21:00+00:00',
      'download_url': url ?? 'http://pos.test/api/v1/mobile-app/android/download',
    });

void main() {
  test('versions compare numerically', () {
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.3.0', '1.3'), 0);
    expect(compareVersions('1.3.0+4', '1.3.0'), 0);
    expect(compareVersions('1.2.9', '1.3.0'), lessThan(0));
  });

  group('fetchNewerRelease', () {
    late FakeBackend backend;
    late ApiClient api;
    // The fake API is http; real builds require https for the link.
    const httpsApi = 'https://pos.test/api/v1';

    setUp(() {
      backend = FakeBackend();
      api = ApiClient(
        baseUrl: 'http://pos.test/api/v1',
        session: SessionStore(InMemoryKeyValueStore()),
        adapter: backend,
        retryDelay: Duration.zero,
      );
    });

    tearDown(() => api.dispose());

    Future<AppRelease?> check(String current) => fetchNewerRelease(api, currentVersion: current, apiBaseUrl: httpsApi);

    test('newer release on the same https host → offered', () async {
      backend.reply('GET', '/mobile-app/android', 200, release(url: 'https://pos.test/api/v1/mobile-app/android/download'));
      final r = await check('1.3.0');
      expect(r?.version, '1.4.0');
      expect(r?.sizeLabel, '26.3 MB');
    });

    test('same or older version → nothing', () async {
      backend.reply('GET', '/mobile-app/android', 200, release(version: '1.3.0', url: 'https://pos.test/x.apk'));
      expect(await check('1.3.0'), isNull);
      expect(await check('1.4.0'), isNull);
    });

    test('a link to another host or plain http is never trusted', () async {
      backend.reply('GET', '/mobile-app/android', 200, release(url: 'https://evil.example/kagoem.apk'));
      expect(await check('1.0.0'), isNull);
      backend.reply('GET', '/mobile-app/android', 200, release(url: 'http://pos.test/x.apk'));
      expect(await check('1.0.0'), isNull);
    });

    test('no APK published, endpoint missing (pos-cashier) or offline → nothing, no error', () async {
      backend.reply('GET', '/mobile-app/android', 200, release(available: false));
      expect(await check('1.0.0'), isNull);
      backend.reply('GET', '/mobile-app/android', 404, {'message': 'The route could not be found.'});
      expect(await check('1.0.0'), isNull);
      backend.failures['GET /mobile-app/android'] = DioExceptionType.connectionError;
      expect(await check('1.0.0'), isNull);
    });

    test('unknown current version (tests, custom builds) → no request at all', () async {
      expect(await check(''), isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('dashboard banner', () {
    late TestHarness h;
    final opened = <Uri>[];

    Future<void> pumpDashboard(WidgetTester tester) async {
      h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
      h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
      h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
      h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...h.overrides,
          currentAppVersionProvider.overrideWithValue('1.3.0'),
          openDownloadProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
        retry: (_, _) => null,
        child: const KagoemPosApp(),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() async {
      opened.clear();
      h = TestHarness();
      await h.session.saveToken('5|tok');
    });

    testWidgets('newer version: banner → Update opens the download link', (tester) async {
      h.backend.reply('GET', '/mobile-app/android', 200, release());
      await pumpDashboard(tester);

      expect(find.text('Update tersedia: versi 1.4.0'), findsOneWidget);
      expect(find.textContaining('Versi terpasang 1.3.0'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-now')));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'http://pos.test/api/v1/mobile-app/android/download');
    });

    testWidgets('"Nanti" hides it for that version, remembered on the device', (tester) async {
      h.backend.reply('GET', '/mobile-app/android', 200, release());
      await pumpDashboard(tester);

      await tester.tap(find.byKey(const Key('update-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-banner')), findsNothing);
      expect(h.deviceStore.values['kagoem.update.dismissed_version'], '1.4.0');
    });

    testWidgets('up to date: no banner', (tester) async {
      h.backend.reply('GET', '/mobile-app/android', 200, release(version: '1.3.0'));
      await pumpDashboard(tester);
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });
  });
}
