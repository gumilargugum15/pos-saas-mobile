import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/utils/currency_formatter.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';

void main() {
  group('Money', () {
    test('parses API numbers and strings exactly', () {
      expect(Money.fromJson(15000), Money.rupiah(15000));
      expect(Money.fromJson(9990.5).minor, 999050);
      expect(Money.fromJson(0.29).minor, 29); // 0.29 * 100 is 28.999… in double
      expect(Money.fromJson('22200.00'), Money.rupiah(22200));
      expect(Money.fromJson('-12.3').minor, -1230);
      expect(Money.fromJson(null), const Money.zero());
    });

    test('rejects malformed strings', () {
      expect(() => Money.parse('12,5'), throwsFormatException);
    });

    test('arithmetic stays exact', () {
      final price = Money.parse('0.10');
      var total = const Money.zero();
      for (var i = 0; i < 10; i++) {
        total += price;
      }
      expect(total, Money.rupiah(1));
      expect(Money.rupiah(10000) * 3, Money.rupiah(30000));
    });

    test('percentOf rounds half away from zero like PHP round(…, 2)', () {
      // SaleServiceTest: 11% of 20000 = 2200; 10% of 10000 = 1000; 11% of 9000 = 990.
      expect(Money.rupiah(20000).percentOf(1100), Money.rupiah(2200));
      expect(Money.rupiah(9000).percentOf(1100), Money.rupiah(990));
      // 11% of 0.05 = 0.0055 → 0.01
      expect(Money.minor(5).percentOf(1100), const Money.minor(1));
      // 12.5% of 0.04 = 0.005 → 0.01
      expect(Money.minor(4).percentOf(1250), const Money.minor(1));
    });

    test('rupiah rounding helpers', () {
      expect(Money.parse('9990.50').rupiahRounded, 9991);
      expect(Money.parse('9990.49').rupiahRounded, 9990);
      expect(Money.parse('9990.01').rupiahCeil, 9991);
      expect(Money.rupiah(9990).rupiahCeil, 9990);
      expect(Money.parse('50000').toDecimalString(), '50000.00');
    });
  });

  group('CurrencyFormatter', () {
    const idr = CurrencyFormatter();

    test('formats like the web POS (Rp, dots, no decimals)', () {
      expect(idr.format(Money.rupiah(10000)), 'Rp 10.000');
      expect(idr.format(Money.rupiah(1250000)), 'Rp 1.250.000');
      expect(idr.format(const Money.zero()), 'Rp 0');
      expect(idr.format(Money.rupiah(999)), 'Rp 999');
      expect(idr.format(Money.rupiah(-2500)), '-Rp 2.500');
      expect(idr.format(Money.parse('9990.50')), 'Rp 9.991');
    });

    test('honours backend settings', () {
      final f = CurrencyFormatter.fromSettings({
        'currency_symbol': 'USD',
        'symbol_position': 'back',
        'decimal_digits': '2',
        'thousand_separator': ',',
        'decimal_separator': '.',
      });
      expect(f.format(Money.parse('1234567.8')), '1,234,567.80 USD');
    });

    test('falls back to defaults for missing settings', () {
      final f = CurrencyFormatter.fromSettings({'currency_symbol': ''});
      expect(f.format(Money.rupiah(35000)), 'Rp 35.000');
    });
  });
}
