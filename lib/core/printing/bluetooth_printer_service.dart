import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_service.dart';

/// Classic Bluetooth (SPP) thermal printers through `print_bluetooth_thermal`.
/// The printer must be paired in Android settings first. This is the only
/// file that knows about the plugin.
class BluetoothPrinterService implements PrinterService {
  String? _connectedAddress;

  @override
  Future<List<PrinterDevice>> devices() async {
    await _ensureReady();
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return [for (final d in paired) PrinterDevice(name: d.name.isEmpty ? d.macAdress : d.name, address: d.macAdress)];
  }

  @override
  Future<void> printBytes(PrinterDevice device, List<int> bytes) async {
    try {
      await _ensureReady();

      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected || _connectedAddress != device.address) {
        if (connected) await PrintBluetoothThermal.disconnect;
        _connectedAddress = null;
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: device.address);
        if (!ok) {
          throw PrinterException(
            'Tidak dapat terhubung ke printer ${device.name}. Pastikan printer menyala dan berada di dekat perangkat.',
          );
        }
        _connectedAddress = device.address;
      }

      final written = await PrintBluetoothThermal.writeBytes(bytes);
      if (!written) {
        _connectedAddress = null;
        throw const PrinterException('Gagal mengirim data ke printer. Coba cetak ulang.');
      }
    } on PrinterException {
      rethrow;
    } on PlatformException catch (e) {
      debugPrint('Bluetooth printing failed: $e');
      _connectedAddress = null;
      throw const PrinterException('Printer tidak merespons. Coba cetak ulang.');
    }
  }

  Future<void> _ensureReady() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw const PrinterException('Izin Bluetooth belum diberikan. Izinkan akses "Perangkat di sekitar" untuk Kagoem POS.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException('Bluetooth mati. Nyalakan Bluetooth lalu coba lagi.');
    }
  }
}
