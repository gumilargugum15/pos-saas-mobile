import 'money.dart';

/// The one place money becomes text. Defaults match the backend
/// `SettingService::DEFAULTS` (Rp, front, 0 decimals, "." thousands, ","
/// decimals); [CurrencyFormatter.fromSettings] applies the tenant's
/// `GET /settings` values once they are loaded.
class CurrencyFormatter {
  const CurrencyFormatter({
    this.symbol = 'Rp',
    this.symbolInFront = true,
    this.decimalDigits = 0,
    this.thousandSeparator = '.',
    this.decimalSeparator = ',',
  });

  factory CurrencyFormatter.fromSettings(Map<String, dynamic> settings) {
    const d = CurrencyFormatter();
    String read(String key, String fallback) {
      final value = settings[key]?.toString();
      return value == null || value.isEmpty ? fallback : value;
    }

    return CurrencyFormatter(
      symbol: read('currency_symbol', d.symbol),
      symbolInFront: read('symbol_position', 'front') != 'back',
      decimalDigits: (int.tryParse(read('decimal_digits', '0')) ?? 0).clamp(0, 2),
      thousandSeparator: read('thousand_separator', d.thousandSeparator),
      decimalSeparator: read('decimal_separator', d.decimalSeparator),
    );
  }

  final String symbol;
  final bool symbolInFront;
  final int decimalDigits;
  final String thousandSeparator;
  final String decimalSeparator;

  /// `Rp 10.000`, `-Rp 2.500`.
  String format(Money amount) {
    final number = formatNumber(amount);
    final negative = number.startsWith('-');
    final digits = negative ? number.substring(1) : number;
    final withSymbol = symbolInFront ? '$symbol $digits' : '$digits $symbol';
    return negative ? '-$withSymbol' : withSymbol;
  }

  /// `10.000` (no symbol), for compact cells and inputs.
  String formatNumber(Money amount) {
    final negative = amount.isNegative;
    final abs = amount.minor.abs();

    final String whole;
    final String fraction;
    if (decimalDigits == 0) {
      whole = ((abs + 50) ~/ 100).toString();
      fraction = '';
    } else if (decimalDigits == 1) {
      final tenths = (abs + 5) ~/ 10;
      whole = (tenths ~/ 10).toString();
      fraction = (tenths % 10).toString();
    } else {
      whole = (abs ~/ 100).toString();
      fraction = (abs % 100).toString().padLeft(2, '0');
    }

    final grouped = _group(whole);
    final result = fraction.isEmpty ? grouped : '$grouped$decimalSeparator$fraction';
    return negative && result.replaceAll(RegExp(r'[^1-9]'), '').isNotEmpty ? '-$result' : result;
  }

  String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(thousandSeparator);
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
