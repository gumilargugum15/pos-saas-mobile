import 'package:flutter/services.dart';

/// Digits-only input shown with thousand separators (`50.000`). The value
/// is whole rupiah; read it with [parseRupiahInput].
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter({this.separator = '.', this.maxDigits = 12});

  final String separator;
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final text = formatRupiahDigits(digits, separator: separator);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

String formatRupiahDigits(String digits, {String separator = '.'}) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

int? parseRupiahInput(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}
