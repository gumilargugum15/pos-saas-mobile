import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../test/data/catalog_repository_test.dart' show page, productJson;
import '../test/features/checkout/checkout_controller_test.dart' show saleJson;
import '../test/helpers/fake_backend.dart';
import '../test/helpers/test_app.dart';

/// The whole cashier journey on a real Android device/emulator, against an
/// in-memory backend (no server or printer needed):
///
///   login → dashboard → scan code → cart → cash payment → success
///   → print receipt → new transaction → history → detail.
///
/// Run: `flutter test integration_test -d <device-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cashier sells, prints and finds the sale in history', (tester) async {
    await initializeDateFormatting('id');
    final h = TestHarness();
    h.deviceStore.values['kagoem.printer.address'] = '00:11:22:33:44:55';
    h.deviceStore.values['kagoem.printer.name'] = 'RPP02N';

    h.backend.reply('POST', '/auth/login', 200, ok({'user': userJson(), 'token': '5|tok'}));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok({'company_name': 'Kagoem Mart', 'receipt_paper_size': '58mm'}));
    h.backend.reply('GET', '/dashboard', 200, ok({
      'stats': {'today_sales': 0, 'transactions_count': 0, 'products_count': 1},
    }));
    h.backend.reply('GET', '/categories', 200, page([]));
    h.backend.reply('GET', '/products', 200, page([
      productJson(id: 1, name: 'Kopi', sku: 'KOPI-01', barcode: '8991234567890', price: 10000, stock: 5),
    ]));
    h.backend.reply('POST', '/sales', 201, ok(saleJson(paid: 10000)));
    h.backend.reply('GET', '/sales', 200, page([saleJson(paid: 10000)]));
    h.backend.reply('GET', '/sales/55', 200, ok(saleJson(paid: 10000)));

    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();

    // Login
    await tester.enterText(find.byKey(const Key('login-email')), 'siti@toko.id');
    await tester.enterText(find.byKey(const Key('login-password')), 'rahasia');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Siti Kasir'), findsOneWidget);

    // POS: a keyboard-wedge scan of the barcode
    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-search')), '8991234567890');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // The search field keeps focus for the next scan; on a phone the soft
    // keyboard then covers the bottom bar, so close it like a cashier would.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // Cart → checkout (phone shows the summary bar; tablets the side pane)
    final openCart = find.byKey(const Key('cart-open'));
    if (openCart.evaluate().isNotEmpty) {
      await tester.tap(openCart);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('cart-checkout')));
    await tester.pumpAndSettle();

    // Cash, exact amount
    await tester.tap(find.byKey(const Key('pay-cash')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Uang Pas'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-pay')));
    await tester.pumpAndSettle();

    expect(find.text('TRANSAKSI BERHASIL'), findsOneWidget);
    expect((h.backend.calls('POST', '/sales').single.data as Map)['items'], [
      {'product_id': 1, 'qty': 1},
    ]);

    // Print
    await tester.tap(find.byKey(const Key('receipt-print')));
    await tester.pumpAndSettle();
    expect(latin1.decode(h.printer.printed.single.bytes), contains('TX-261003-00001'));

    // Next customer, then history
    await tester.tap(find.byKey(const Key('new-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi Baru'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final menu = find.widgetWithText(InkWell, 'Transaksi');
    await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TX-261003-00001'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Transaksi'), findsOneWidget);
  });
}
