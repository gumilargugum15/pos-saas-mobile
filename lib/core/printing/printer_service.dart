/// A printer the device can talk to (for Bluetooth: a paired device).
class PrinterDevice {
  const PrinterDevice({required this.name, required this.address});

  final String name;

  /// Bluetooth MAC address.
  final String address;

  @override
  bool operator ==(Object other) => other is PrinterDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;
}

/// Why printing failed, in words a cashier can act on.
class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Printer transport. The app only depends on this interface; the
/// Bluetooth library lives in a single implementation, so another
/// transport (USB, network, a different plugin) can be swapped in.
abstract interface class PrinterService {
  /// Printers available to choose from (paired Bluetooth devices).
  Future<List<PrinterDevice>> devices();

  /// Sends raw ESC/POS bytes. Throws [PrinterException].
  Future<void> printBytes(PrinterDevice device, List<int> bytes);
}
