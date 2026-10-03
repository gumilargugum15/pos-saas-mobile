import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/printing/bluetooth_printer_service.dart';
import '../../core/printing/escpos_encoder.dart';
import '../../core/printing/printer_service.dart';
import '../../core/storage/session_store.dart';
import '../../domain/entities/sale.dart';
import '../auth/application/session_controller.dart';
import '../settings/settings_providers.dart';
import 'receipt_formatter.dart';

/// Device-level storage for printer choices. Separate from the session, so
/// it survives logout (the till keeps its printer).
final deviceStoreProvider = Provider<SecureKeyValueStore>((ref) => FlutterSecureKeyValueStore());

final printerServiceProvider = Provider<PrinterService>((ref) => BluetoothPrinterService());

/// Shares plain text through the OS share sheet (WhatsApp, email, …).
final textSharerProvider = Provider<Future<void> Function(String text, String subject)>((ref) {
  return (text, subject) => SharePlus.instance.share(ShareParams(text: text, subject: subject));
});

class PrinterSettings {
  const PrinterSettings({this.device, this.paperOverride});

  final PrinterDevice? device;

  /// Null = follow the store setting `receipt_paper_size`.
  final PaperSize? paperOverride;
}

class PrinterSettingsController extends AsyncNotifier<PrinterSettings> {
  static const _nameKey = 'kagoem.printer.name';
  static const _addressKey = 'kagoem.printer.address';
  static const _paperKey = 'kagoem.printer.paper';

  SecureKeyValueStore get _store => ref.read(deviceStoreProvider);

  @override
  Future<PrinterSettings> build() async {
    final store = ref.watch(deviceStoreProvider);
    final address = await store.read(_addressKey);
    final name = await store.read(_nameKey);
    final paper = await store.read(_paperKey);
    return PrinterSettings(
      device: address == null ? null : PrinterDevice(name: name ?? address, address: address),
      paperOverride: paper == null ? null : PaperSize.fromSetting(paper),
    );
  }

  Future<void> setDevice(PrinterDevice? device) async {
    if (device == null) {
      await _store.delete(_addressKey);
      await _store.delete(_nameKey);
    } else {
      await _store.write(_addressKey, device.address);
      await _store.write(_nameKey, device.name);
    }
    final current = state.value ?? const PrinterSettings();
    state = AsyncData(PrinterSettings(device: device, paperOverride: current.paperOverride));
  }

  Future<void> setPaper(PaperSize? paper) async {
    if (paper == null) {
      await _store.delete(_paperKey);
    } else {
      await _store.write(_paperKey, paper.label);
    }
    final current = state.value ?? const PrinterSettings();
    state = AsyncData(PrinterSettings(device: current.device, paperOverride: paper));
  }
}

final printerSettingsProvider =
    AsyncNotifierProvider<PrinterSettingsController, PrinterSettings>(PrinterSettingsController.new);

/// The printer is not set up yet: the UI sends the cashier to the settings.
class PrinterNotConfigured implements Exception {
  const PrinterNotConfigured();
}

/// Receipt preview, print and share for a sale.
class ReceiptActions {
  ReceiptActions(this._ref);

  final Ref _ref;

  PaperSize get paper {
    final override = _ref.read(printerSettingsProvider).value?.paperOverride;
    return override ?? PaperSize.fromSetting(_ref.read(settingsProvider).value?['receipt_paper_size']);
  }

  ReceiptFormatter get formatter =>
      ReceiptFormatter(paper: paper, currency: _ref.read(currencyFormatterProvider));

  ReceiptHeader get header {
    final storeName = _ref.read(settingsProvider).value?['company_name'];
    return ReceiptHeader(
      storeName: storeName == null || storeName.trim().isEmpty ? 'Kagoem POS' : storeName.trim(),
      tenantName: _ref.read(activeTenantProvider)?.name,
    );
  }

  List<ReceiptLine> lines(Sale sale) => formatter.format(sale, header);

  String plainText(Sale sale) => formatter.toPlainText(lines(sale));

  /// Throws [PrinterNotConfigured] or [PrinterException].
  Future<void> print(Sale sale) => _send(EscPosEncoder.encode(lines(sale)));

  Future<void> printTest() => _send(EscPosEncoder.encode(formatter.testPage()));

  Future<void> share(Sale sale) => _ref.read(textSharerProvider)(plainText(sale), 'Struk ${sale.invoiceNumber}');

  Future<void> _send(List<int> bytes) async {
    final device = (await _ref.read(printerSettingsProvider.future)).device;
    if (device == null) throw const PrinterNotConfigured();
    await _ref.read(printerServiceProvider).printBytes(device, bytes);
  }
}

final receiptActionsProvider = Provider<ReceiptActions>((ref) {
  // Keep the inputs loaded while receipts can be printed.
  ref.watch(settingsProvider);
  ref.watch(printerSettingsProvider);
  return ReceiptActions(ref);
});
