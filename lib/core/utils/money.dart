/// An exact money amount in minor units (sen, 1/100 rupiah), matching the
/// backend's DECIMAL(18,2) columns. Arithmetic never goes through `double`.
class Money implements Comparable<Money> {
  const Money.minor(this.minor);

  const Money.zero() : minor = 0;

  factory Money.rupiah(int rupiah) => Money.minor(rupiah * 100);

  /// Parses an API amount. The backend Resources send money as JSON numbers
  /// (`(float)` cast) with at most 2 decimals; strings are parsed exactly.
  factory Money.fromJson(Object? value) {
    if (value == null) return const Money.zero();
    if (value is int) return Money.minor(value * 100);
    if (value is num) return Money.minor((value * 100).round());
    return Money.parse(value.toString());
  }

  /// Parses a plain decimal string such as `"15000"`, `"9990.5"` or `"-12.34"`.
  factory Money.parse(String input) {
    final match = RegExp(r'^\s*(-?)(\d+)(?:\.(\d{1,2})\d*)?\s*$').firstMatch(input);
    if (match == null) throw FormatException('Invalid money amount', input);
    final negative = match.group(1) == '-';
    final whole = int.parse(match.group(2)!);
    final fraction = int.parse((match.group(3) ?? '0').padRight(2, '0'));
    final minor = whole * 100 + fraction;
    return Money.minor(negative ? -minor : minor);
  }

  final int minor;

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;

  /// Whole rupiah, rounded half away from zero (PHP `round()` semantics).
  int get rupiahRounded {
    final abs = minor.abs();
    final rounded = (abs + 50) ~/ 100;
    return minor < 0 ? -rounded : rounded;
  }

  /// Whole rupiah, rounded up (used to prefill non-cash payments, like the web POS).
  int get rupiahCeil {
    if (minor <= 0) return -((-minor) ~/ 100);
    return (minor + 99) ~/ 100;
  }

  /// Decimal string for request bodies, e.g. `"50000.00"`.
  String toDecimalString() {
    final abs = minor.abs();
    final sign = minor < 0 ? '-' : '';
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  Money operator +(Money other) => Money.minor(minor + other.minor);
  Money operator -(Money other) => Money.minor(minor - other.minor);
  Money operator *(int factor) => Money.minor(minor * factor);
  Money operator -() => Money.minor(-minor);
  bool operator <(Money other) => minor < other.minor;
  bool operator <=(Money other) => minor <= other.minor;
  bool operator >(Money other) => minor > other.minor;
  bool operator >=(Money other) => minor >= other.minor;

  /// `this × percent / 100`, rounded half away from zero to the sen, the same
  /// as `round($amount * ($percent / 100), 2)` in the backend SaleService.
  /// [percentHundredths] is the percentage × 100 (11% → 1100, 12.5% → 1250).
  Money percentOf(int percentHundredths) {
    final product = minor * percentHundredths;
    const divisor = 10000;
    final abs = product.abs();
    final rounded = (abs + divisor ~/ 2) ~/ divisor;
    return Money.minor(product < 0 ? -rounded : rounded);
  }

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money(${toDecimalString()})';
}
