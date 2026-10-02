import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/domain/entities/cart.dart';
import 'package:kagoem_pos_mobile/domain/entities/product.dart';
import 'package:kagoem_pos_mobile/domain/usecases/match_scanned_code.dart';

Product product({
  int id = 1,
  int price = 10000,
  int stock = 10,
  int tax = 1100,
  int discount = 0,
  String? barcode,
  String sku = 'SKU-1',
  bool active = true,
}) =>
    Product(
      id: id,
      name: 'P$id',
      sku: sku,
      barcode: barcode,
      price: Money.rupiah(price),
      stock: stock,
      taxHundredths: tax,
      discountHundredths: discount,
      isActive: active,
    );

void main() {
  group('Cart totals mirror SaleService::checkout', () {
    test('backend test: 2 × 10.000, tax 11% → grand total 22.200', () {
      final cart = Cart([CartLine(product: product(), qty: 2)]);
      expect(cart.subtotal, Money.rupiah(20000));
      expect(cart.discountTotal, const Money.zero());
      expect(cart.taxTotal, Money.rupiah(2200));
      expect(cart.grandTotal, Money.rupiah(22200));
    });

    test('backend test: discount 10% then tax 11% → 9.990', () {
      final cart = Cart([CartLine(product: product(discount: 1000), qty: 1)]);
      expect(cart.discountTotal, Money.rupiah(1000));
      expect(cart.taxTotal, Money.rupiah(990));
      expect(cart.grandTotal, Money.rupiah(9990));
    });

    test('rounding is per line, like the backend', () {
      // 3 × 3.333 = 9.999; disc 12.5% = 1249.875 → 1249.88; tax 11% of 8749.12 = 962.4032 → 962.40
      final line = CartLine(product: product(price: 3333, discount: 1250), qty: 3);
      expect(line.gross, Money.rupiah(9999));
      expect(line.discount, Money.parse('1249.88'));
      expect(line.tax, Money.parse('962.40'));
      expect(line.subtotal, Money.parse('9711.52'));
    });

    test('multiple lines and request items', () {
      final cart = Cart([
        CartLine(product: product(id: 1, tax: 0), qty: 2),
        CartLine(product: product(id: 2, price: 15000, tax: 0), qty: 1),
      ]);
      expect(cart.itemCount, 3);
      expect(cart.grandTotal, Money.rupiah(35000));
      expect(cart.toSaleItems(), [
        {'product_id': 1, 'qty': 2},
        {'product_id': 2, 'qty': 1},
      ]);
    });
  });

  group('matchScannedCode', () {
    final items = [
      product(id: 1, barcode: '8991234567890', sku: 'KOPI-01'),
      product(id: 2, barcode: '8991234567', sku: 'TEH-01'),
      product(id: 3, barcode: null, sku: '8991234567890X'),
    ];

    test('exact barcode wins', () => expect(matchScannedCode(items, '8991234567890')?.id, 1));

    test('exact SKU matches when no barcode does', () => expect(matchScannedCode(items, 'TEH-01')?.id, 2));

    test('partial/LIKE matches are never accepted', () {
      expect(matchScannedCode(items, '89912345'), isNull);
      expect(matchScannedCode(items, 'KOPI'), isNull);
    });

    test('surrounding whitespace from scanners is ignored', () {
      expect(matchScannedCode(items, ' 8991234567890\n')?.id, 1);
    });

    test('inactive products are not matched', () {
      expect(matchScannedCode([product(barcode: '123', active: false)], '123'), isNull);
    });
  });
}
