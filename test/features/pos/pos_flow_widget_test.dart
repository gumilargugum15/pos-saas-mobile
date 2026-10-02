import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../../data/catalog_repository_test.dart' show page, productJson;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

void main() {
  late TestHarness h;

  setUp(() async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok({'currency_symbol': 'Rp', 'decimal_digits': '0'}));
    h.backend.reply('GET', '/dashboard', 200, ok({
      'stats': {'today_sales': 1250000.0, 'transactions_count': 32, 'products_count': 1245, 'today_profit': 999999.0},
    }));
    h.backend.reply('GET', '/categories', 200, page([
      {'id': 2, 'name': 'Minuman', 'slug': 'minuman', 'is_active': true},
    ]));
    h.backend.on('GET', '/products', (request) {
      final search = request.uri.queryParameters['search'];
      final all = [
        productJson(id: 1, name: 'Kopi Susu', sku: 'KOPI-01', barcode: '8991234567890', price: 10000, stock: 5),
        productJson(id: 2, name: 'Teh Manis', sku: 'TEH-01', barcode: '8990000000001', price: 15000, stock: 0),
      ];
      final items = search == null
          ? all
          : all.where((p) => '${p['name']} ${p['sku']} ${p['barcode']}'.toLowerCase().contains(search.toLowerCase())).toList();
      return (status: 200, body: page(items));
    });
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('dashboard shows cashier info and tenant-wide figures, never profit', (tester) async {
    await pumpApp(tester, const Size(420, 900));

    expect(find.text('Siti Kasir'), findsOneWidget);
    expect(find.text('Toko Pusat'), findsOneWidget);
    expect(find.text('Rp 1.250.000'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(find.text('1245'), findsOneWidget);
    expect(find.textContaining('999.999'), findsNothing);
  });

  testWidgets('phone: tap products, open cart, change quantity, see totals', (tester) async {
    await pumpApp(tester, const Size(420, 900));
    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();

    expect(find.text('Kopi Susu'), findsOneWidget);
    expect(find.text('Minuman'), findsOneWidget); // category chip
    expect(find.text('Habis'), findsOneWidget);

    await tester.tap(find.text('Kopi Susu'));
    await tester.tap(find.text('Kopi Susu'));
    await tester.pump();
    // 2 × 10.000, discount 12.5% = 2.500, tax 11% of 17.500 = 1.925 → 19.425
    expect(find.text('2 item'), findsOneWidget);
    expect(find.text('Rp 19.425'), findsOneWidget);

    // Out of stock product is refused.
    await tester.tap(find.text('Teh Manis'));
    await tester.pump();
    expect(find.text('Teh Manis sedang habis stok.'), findsOneWidget);
    expect(find.text('2 item'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cart-open')));
    await tester.pumpAndSettle();
    expect(find.text('Keranjang (2)'), findsOneWidget);
    expect(find.text('Rp 10.000 × 2'), findsOneWidget);
    expect(find.text('Rp 20.000'), findsNWidgets(2)); // line gross + subtotal
    expect(find.text('-Rp 2.500'), findsOneWidget);
    expect(find.text('Rp 1.925'), findsOneWidget);
    expect(find.text('Rp 19.425'), findsOneWidget);

    // Manual quantity above stock is limited to the stock.
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('qty-input')), '9');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Keranjang (5)'), findsOneWidget);
    expect(find.textContaining('tidak mencukupi (tersisa 5)'), findsOneWidget);

    // Clear cart with confirmation.
    await tester.tap(find.byKey(const Key('cart-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kosongkan').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Keranjang masih kosong'), findsOneWidget);
  });

  testWidgets('tablet: catalog and cart side by side; hardware scanner adds by exact barcode', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-checkout')), findsOneWidget);
    expect(find.byKey(const Key('cart-open')), findsNothing);

    // A keyboard-wedge scanner types the code and presses Enter.
    await tester.enterText(find.byKey(const Key('catalog-search')), '8991234567890');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Keranjang (1)'), findsOneWidget);
    expect(find.text('Kopi Susu ditambahkan (×1)'), findsOneWidget);
    // Field cleared, ready for the next scan.
    expect(tester.widget<TextField>(find.byKey(const Key('catalog-search'))).controller!.text, isEmpty);
  });

  testWidgets('unknown code stays as a search and adds nothing', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('catalog-search')), '0000000000000');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.textContaining('Keranjang masih kosong'), findsOneWidget);
    expect(find.text('Produk "0000000000000" tidak ditemukan.'), findsOneWidget);
  });
}
