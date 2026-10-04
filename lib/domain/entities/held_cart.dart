import '../../core/utils/money.dart';
import 'cart.dart';
import 'party.dart';

/// A cart parked on this device to finish later ("hold transaction").
///
/// Holds never reach the backend (the web POS keeps them in localStorage
/// too): nothing is sold, reserved or deducted from stock until the cart
/// is resumed and checked out.
class HeldCart {
  const HeldCart({
    required this.id,
    required this.lines,
    required this.createdAt,
    this.customer,
    this.note,
  });

  final String id;

  /// Product snapshots as they were when held; refreshed on resume.
  final List<CartLine> lines;
  final DateTime createdAt;

  /// Null = walk-in.
  final Customer? customer;

  /// Optional cashier note, e.g. "Meja 3" or "Bapak baju merah".
  final String? note;

  /// Shown in the list: the note, else the customer, else "Walk-in"
  /// (the web POS labels holds by customer name).
  String get label {
    final n = note?.trim();
    if (n != null && n.isNotEmpty) return n;
    return customer?.name ?? 'Walk-in';
  }

  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);

  /// Total at the time of holding (prices may change before resume).
  Money get estimatedTotal => Cart(lines).grandTotal;
}
