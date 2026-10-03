import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kagoem_pos_mobile/core/config/app_config.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/printing/printer_service.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';
import 'package:kagoem_pos_mobile/features/receipt/receipt_providers.dart';

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
  final deviceStore = InMemoryKeyValueStore();
  final printer = FakePrinterService();
  final shared = <({String text, String subject})>[];

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
        deviceStoreProvider.overrideWithValue(deviceStore),
        printerServiceProvider.overrideWithValue(printer),
        textSharerProvider.overrideWithValue((text, subject) async => shared.add((text: text, subject: subject))),
      ];

  ProviderContainer container() => ProviderContainer(overrides: overrides, retry: (_, _) => null);
}

class FakePrinterService implements PrinterService {
  List<PrinterDevice> paired = const [PrinterDevice(name: 'RPP02N', address: '00:11:22:33:44:55')];
  final List<({PrinterDevice device, List<int> bytes})> printed = [];

  /// When set, printing fails with this message.
  String? failWith;

  @override
  Future<List<PrinterDevice>> devices() async => paired;

  @override
  Future<void> printBytes(PrinterDevice device, List<int> bytes) async {
    if (failWith != null) throw PrinterException(failWith!);
    printed.add((device: device, bytes: bytes));
  }
}
