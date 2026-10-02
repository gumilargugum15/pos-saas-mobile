import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../../data/catalog_repository_test.dart' show page, productJson;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';
import 'checkout_controller_test.dart' show saleJson;

void main() {
  late TestHarness h;

  setUp(() async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
    h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
    h.backend.reply('GET', '/categories', 200, page([]));
    h.backend.reply('GET', '/products', 200, page([productJson(id: 1, name: 'Kopi Susu', price: 10000, stock: 5)]));
    h.backend.reply('GET', '/sales', 200, page([saleJson()]));
    h.backend.reply('GET', '/sales/55', 200, ok(saleJson()));
  });

  testWidgets('cash sale end to end on a phone, then find it in the history', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 1 × 10.000, discount 12.5% (1.250), tax 11% of 8.750 (962,50) → 9.712,50
    // → the cashier charges Rp 9.713. The server is the source of truth.
    h.backend.reply('POST', '/sales', 201, ok({
      ...saleJson(paid: 10000),
      'grand_total': 9712.5,
      'change_amount': 287.5,
    }));

    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-transaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopi Susu'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cart-open')));
    await tester.pumpAndSettle();
    expect(find.text('Keranjang (1)'), findsOneWidget); // single title on phones

    await tester.tap(find.byKey(const Key('cart-checkout')));
    await tester.pumpAndSettle();
    expect(find.text('Walk-in'), findsOneWidget);
    expect(find.text('Pilih metode pembayaran.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pay-cash')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('cash-change')), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byKey(const Key('cash-received')), '5000');
    await tester.pump();
    expect(find.text('Kurang Rp 4.713'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('checkout-pay'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('cash-received')), '10000');
    await tester.pump();
    expect(find.text('10.000'), findsOneWidget); // thousand separators while typing
    expect(find.byKey(const Key('cash-change')), findsOneWidget);
    expect(find.text('Rp 287'), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkout-pay')));
    await tester.pumpAndSettle();

    final body = h.backend.calls('POST', '/sales').single.data as Map;
    expect(body['paid_amount'], 10000);
    expect(body['items'], [
      {'product_id': 1, 'qty': 1},
    ]);

    expect(find.text('TRANSAKSI BERHASIL'), findsOneWidget);
    expect(find.text('TX-261003-00001'), findsOneWidget);
    expect(find.text('Tunai'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-transaction')));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi Baru'), findsOneWidget);
    expect(find.text('Keranjang kosong'), findsOneWidget);

    // Back to the dashboard → history → detail.
    await tester.tap(find.byType(BackButton)); // pageBack() looks for the English 'Back' tooltip
    await tester.pumpAndSettle();
    final menu = find.widgetWithText(InkWell, 'Transaksi');
    await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Riwayat Transaksi'), findsOneWidget);
    expect(find.text('TX-261003-00001'), findsOneWidget);
    final list = h.backend.calls('GET', '/sales').last.uri.queryParameters;
    expect(list['date_from'], isNotNull, reason: 'defaults to today');
    expect(list['date_from'], list['date_to']);

    await tester.tap(find.text('TX-261003-00001'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Transaksi'), findsOneWidget);
    expect(find.text('Siti Kasir'), findsOneWidget);
    expect(find.text('Kopi'), findsOneWidget);
  });
}
