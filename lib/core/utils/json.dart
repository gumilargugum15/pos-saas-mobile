/// Lenient readers for backend JSON: Laravel may serialize the same field as
/// a number or a numeric string depending on the column cast.
abstract final class Json {
  static int asInt(Object? value, {int fallback = 0}) => asIntOrNull(value) ?? fallback;

  static int? asIntOrNull(Object? value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v) ?? double.tryParse(v)?.toInt(),
        _ => null,
      };

  static String asString(Object? value, {String fallback = ''}) => asStringOrNull(value) ?? fallback;

  static String? asStringOrNull(Object? value) => value?.toString();

  static bool asBool(Object? value, {bool fallback = false}) => switch (value) {
        bool v => v,
        num v => v != 0,
        String v => v == '1' || v.toLowerCase() == 'true',
        _ => fallback,
      };

  static List<String> asStringList(Object? value) =>
      value is List ? [for (final v in value) v.toString()] : const [];

  static List<String>? asStringListOrNull(Object? value) => value is List ? asStringList(value) : null;

  /// A DECIMAL(5,2) percentage as an exact integer in hundredths
  /// (11 → 1100, 12.5 → 1250), for integer money math.
  static int asHundredths(Object? value) => switch (value) {
        int v => v * 100,
        num v => (v * 100).round(),
        String v => ((double.tryParse(v) ?? 0) * 100).round(),
        _ => 0,
      };

  static Map<String, dynamic> asMap(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const {};
}
