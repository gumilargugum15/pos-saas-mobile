import '../../features/receipt/receipt_formatter.dart';

/// Minimal ESC/POS byte stream, the same command set as the web POS
/// (frontend/src/lib/escpos.ts): init, align, bold, text, feed, cut. Works
/// on common 58/80mm thermal printers without a vendor library.
abstract final class EscPosEncoder {
  static const _esc = 0x1b;
  static const _gs = 0x1d;
  static const _lf = 0x0a;

  static List<int> encode(List<ReceiptLine> lines, {int feedLines = 3, bool cut = true}) {
    final bytes = <int>[_esc, 0x40]; // initialize
    LineAlign? align;
    var bold = false;

    for (final line in lines) {
      if (line.align != align) {
        align = line.align;
        bytes.addAll([_esc, 0x61, align == LineAlign.center ? 1 : 0]);
      }
      if (line.bold != bold) {
        bold = line.bold;
        bytes.addAll([_esc, 0x45, bold ? 1 : 0]);
      }
      bytes
        ..addAll(_text(line.text))
        ..add(_lf);
    }

    if (bold) bytes.addAll([_esc, 0x45, 0]);
    for (var i = 0; i < feedLines; i++) {
      bytes.add(_lf);
    }
    if (cut) bytes.addAll([_gs, 0x56, 0x00]);
    return bytes;
  }

  /// Thermal printers use a single-byte code page: anything outside Latin-1
  /// (emoji, CJK) is printed as '?', control characters are dropped.
  static Iterable<int> _text(String text) sync* {
    for (final rune in text.runes) {
      if (rune < 0x20) continue;
      yield rune < 0x100 ? rune : 0x3f;
    }
  }
}
