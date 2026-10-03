import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../../data/catalog_repository_test.dart' show page, productJson;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';
import '../checkout/checkout_controller_test.dart' show saleJson;

void main() {
  late TestHarness h;

  setUp(() async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok({'company_name': 'Kagoem Mart', 'receipt_paper_size': '58mm'}));
    h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
    h.backend.reply('GET', '/categories', 200, page([]));
    h.backend.reply('GET', '/products', 200, page([productJson(id: 1, name: 'Kopi', price: 10000, stock: 5)]));
    h.backend.reply('POST', '/sales', 201, ok(saleJson()));
    h.backend.reply('GET', '/sales', 200, page([saleJson()]));
    h.backend.reply('GET', '/sales/55', 200, ok(saleJson()));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();
  }

  Future<void> sellOneKopi(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cart-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cart-checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-qris')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.text('TRANSAKSI BERHASIL'), findsOneWidget);
  }

  testWidgets('print after a sale: set up printer when missing, then print; failures never crash', (tester) async {
    await pumpApp(tester);
    await sellOneKopi(tester);

    // No printer yet → guided to the printer settings.
    await tester.tap(find.byKey(const Key('receipt-print')));
    await tester.pumpAndSettle();
    expect(find.text('Printer belum diatur'), findsOneWidget);
    await tester.tap(find.text('Atur Printer'));
    await tester.pumpAndSettle();
    expect(find.text('Printer Struk'), findsOneWidget);
    expect(find.text('Ikuti toko (58mm)'), findsOneWidget);

    await tester.tap(find.text('RPP02N'));
    await tester.pumpAndSettle();
    expect(h.deviceStore.values['kagoem.printer.address'], '00:11:22:33:44:55');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('TRANSAKSI BERHASIL'), findsOneWidget);

    // Print: ESC/POS for a 58mm receipt with the store name and invoice.
    await tester.tap(find.byKey(const Key('receipt-print')));
    await tester.pumpAndSettle();
    final printed = h.printer.printed.single;
    expect(printed.device.address, '00:11:22:33:44:55');
    expect(printed.bytes.take(2), [0x1b, 0x40]);
    final text = latin1.decode(printed.bytes);
    expect(text, contains('Kagoem Mart'));
    expect(text, contains('Toko ABC'));
    expect(text, contains('TX-261003-00001'));
    expect(find.text('Struk dicetak.'), findsOneWidget);

    // Printer off: a message, the sale screen stays.
    h.printer.failWith = 'Bluetooth mati. Nyalakan Bluetooth lalu coba lagi.';
    await tester.tap(find.byKey(const Key('receipt-print')));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth mati. Nyalakan Bluetooth lalu coba lagi.'), findsOneWidget);
    expect(find.text('TRANSAKSI BERHASIL'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Share as text.
    await tester.tap(find.byKey(const Key('receipt-share')));
    await tester.pumpAndSettle();
    expect(h.shared.single.subject, 'Struk TX-261003-00001');
    expect(h.shared.single.text, contains('TOTAL'));
  });

  testWidgets('reprint from transaction history', (tester) async {
    h.deviceStore.values['kagoem.printer.address'] = '00:11:22:33:44:55';
    h.deviceStore.values['kagoem.printer.name'] = 'RPP02N';
    await pumpApp(tester);

    final menu = find.widgetWithText(InkWell, 'Transaksi');
    await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TX-261003-00001'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-receipt')));
    await tester.pumpAndSettle();

    expect(find.text('Struk'), findsOneWidget);
    expect(find.textContaining('TX-261003-00001'), findsOneWidget); // preview
    await tester.tap(find.byKey(const Key('receipt-print')));
    await tester.pumpAndSettle();
    expect(h.printer.printed, hasLength(1));
  });
}
