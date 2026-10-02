import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kagoem_pos_mobile/core/config/app_config.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';

import 'fake_backend.dart';

const testConfig = AppConfig(environment: AppEnvironment.development, apiBaseUrl: 'http://pos.test/api/v1');

/// Real providers (repositories, session controller) on top of a fake HTTP
/// backend and in-memory secure storage.
class TestHarness {
  TestHarness({SessionStore? session})
      : backend = FakeBackend(),
        store = InMemoryKeyValueStore() {
    this.session = session ?? SessionStore(store);
  }

  final FakeBackend backend;
  final InMemoryKeyValueStore store;
  late final SessionStore session;

  List<Override> get overrides => [
        appConfigProvider.overrideWithValue(testConfig),
        sessionStoreProvider.overrideWithValue(session),
        apiClientProvider.overrideWith((ref) {
          final client = ApiClient(
            baseUrl: testConfig.apiBaseUrl,
            session: session,
            adapter: backend,
            retryDelay: Duration.zero,
          );
          ref.onDispose(client.dispose);
          return client;
        }),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides, retry: (_, _) => null);
}
