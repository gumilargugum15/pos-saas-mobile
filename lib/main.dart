import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on ConfigException catch (e) {
    runApp(_ConfigErrorApp(e.message));
    return;
  }

  await initializeDateFormatting('id');

  final session = SessionStore(FlutterSecureKeyValueStore());
  await session.load();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        sessionStoreProvider.overrideWithValue(session),
      ],
      // Requests are retried deliberately in ApiClient (GET only), never by
      // the provider framework: a retried write could duplicate a sale.
      retry: (_, _) => null,
      child: const KagoemPosApp(),
    ),
  );
}

/// Shown instead of the app when the build has no valid environment file.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('Konfigurasi aplikasi tidak valid.\n\n$message', textAlign: TextAlign.center)),
          ),
        ),
      ),
    );
  }
}
