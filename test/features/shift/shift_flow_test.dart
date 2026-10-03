import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';
import 'package:kagoem_pos_mobile/domain/entities/shift.dart';

import '../../data/catalog_repository_test.dart' show page;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

/// A tiny stateful fake of ShiftService / CashTransactionService.
class FakeDrawer {
  Map<String, dynamic>? shift;
  final movements = <Map<String, dynamic>>[];
  num cashSales = 50000;

  num get _in => movements.where((m) => m['type'] == 'in').fold<num>(0, (s, m) => s + (m['amount'] as num));
  num get _out => movements.where((m) => m['type'] == 'out').fold<num>(0, (s, m) => s + (m['amount'] as num));
  num get expected => (shift?['opening_balance'] as num? ?? 0) + cashSales + _in - _out;

  void install(FakeBackend backend) {
    backend.on('GET', '/shifts/current', (_) => (
          status: 200,
          body: ok(shift == null
              ? {'shift': null, 'live': null}
              : {
                  'shift': shift,
                  'live': {'cash_sales': cashSales, 'cash_in_total': _in, 'cash_out_total': _out, 'expected_balance': expected},
                }),
        ));
    backend.on('POST', '/shifts', (r) {
      if (shift != null) {
        return (status: 422, body: validationError({'user_id': ['Anda sudah memiliki shift yang sedang berjalan.']}));
      }
      final body = r.data as Map;
      shift = {
        'id': 9,
        'status': 'open',
        'branch_id': 3,
        'branch_name': 'Toko Pusat',
        'opening_balance': body['opening_balance'],
        'closing_balance': null,
        'expected_balance': null,
        'variance': null,
        'notes': body['notes'],
        'opened_at': '2026-10-03T08:00:00+07:00',
        'closed_at': null,
      };
      return (status: 201, body: ok(shift));
    });
    backend.on('GET', '/cash-transactions', (_) => (status: 200, body: page(movements.reversed.toList())));
    backend.on('POST', '/cash-transactions', (r) {
      if (shift == null) {
        return (status: 422, body: validationError({'shift_id': ['Anda belum membuka shift. Buka shift terlebih dahulu.']}));
      }
      final body = r.data as Map;
      final m = {
        'id': movements.length + 1,
        'reference_number': 'FIN-261003-0000${movements.length + 1}',
        'shift_id': 9,
        'type': body['type'],
        'category': body['category'],
        'amount': body['amount'],
        'description': body['description'],
        'created_at': '2026-10-03T09:00:00+07:00',
      };
      movements.add(m);
      return (status: 201, body: ok(m));
    });
    backend.on('POST', '/shifts/9/close', (r) {
      final closing = (r.data as Map)['closing_balance'] as num;
      final closed = {
        ...shift!,
        'status': 'closed',
        'closing_balance': closing,
        'expected_balance': expected,
        'variance': closing - expected,
        'closed_at': '2026-10-03T17:00:00+07:00',
      };
      shift = null;
      movements.clear();
      return (status: 200, body: ok(closed));
    });
  }
}

void main() {
  late TestHarness h;
  late FakeDrawer drawer;

  setUp(() async {
    h = TestHarness();
    drawer = FakeDrawer()..install(h.backend);
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
    h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key(key)), text);
    await tester.pump();
  }

  testWidgets('open shift → cash in/out → close with a counted shortfall', (tester) async {
    await pumpApp(tester);
    expect(find.text('Belum ada shift aktif'), findsOneWidget); // dashboard card

    await tester.tap(find.byKey(const Key('dashboard-shift')));
    await tester.pumpAndSettle();

    // Open with Rp 200.000 float
    await tester.tap(find.byKey(const Key('shift-open')));
    await tester.pumpAndSettle();
    await enter(tester, 'shift-opening', '200000');
    expect(find.text('200.000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shift-open-submit')));
    await tester.pumpAndSettle();
    expect((h.backend.calls('POST', '/shifts').single.data as Map)['opening_balance'], 200000);
    expect(find.text('Rp 250.000'), findsOneWidget); // 200.000 + 50.000 cash sales

    // Cash in: capital deposit 100.000
    await tester.tap(find.byKey(const Key('cash-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setoran Modal'));
    await enter(tester, 'cash-amount', '100000');
    await enter(tester, 'cash-description', 'Tambah modal kembalian');
    await tester.tap(find.byKey(const Key('cash-submit')));
    await tester.pumpAndSettle();

    // Cash out: operational expense 30.000
    await tester.tap(find.byKey(const Key('cash-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kas Keluar'));
    await tester.pumpAndSettle();
    await enter(tester, 'cash-amount', '30000');
    await enter(tester, 'cash-description', 'Beli plastik');
    await tester.tap(find.byKey(const Key('cash-submit')));
    await tester.pumpAndSettle();

    final posted = h.backend.calls('POST', '/cash-transactions').map((r) => r.data as Map).toList();
    expect(posted[0], {'branch_id': null, 'type': 'in', 'category': 'deposit', 'amount': 100000, 'description': 'Tambah modal kembalian'});
    expect(posted[1], {'branch_id': null, 'type': 'out', 'category': 'expense', 'amount': 30000, 'description': 'Beli plastik'});
    expect(find.text('Rp 320.000'), findsOneWidget); // 200 + 50 + 100 − 30
    expect(find.text('Beli plastik'), findsOneWidget);
    expect(find.text('-Rp 30.000'), findsNWidgets(2)); // "Kas keluar" total + the entry

    // Close: counted 315.000 → 5.000 short
    await tester.tap(find.byKey(const Key('shift-close')));
    await tester.pumpAndSettle();
    await enter(tester, 'shift-counted', '315000');
    expect(find.text('Kurang Rp 5.000'), findsOneWidget); // preview
    await tester.tap(find.byKey(const Key('shift-close-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shift-closed-result')), findsOneWidget);
    expect(find.text('Kas kurang'), findsOneWidget);
    expect(find.text('-Rp 5.000'), findsOneWidget); // server variance
    expect(find.text('Belum ada shift aktif'), findsOneWidget);
  });

  testWidgets('server rules are shown as-is (shift already open)', (tester) async {
    drawer.shift = {
      'id': 9,
      'status': 'open',
      'opening_balance': 100000,
      'opened_at': '2026-10-03T08:00:00+07:00',
    };
    await pumpApp(tester);
    expect(find.textContaining('Shift aktif'), findsOneWidget);
    // The open button is not offered while a shift is open.
    await tester.tap(find.byKey(const Key('dashboard-shift')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shift-open')), findsNothing);
    expect(find.byKey(const Key('shift-close')), findsOneWidget);
  });

  testWidgets('users without operate-cash-drawer do not see the drawer', (tester) async {
    h.backend.reply('GET', '/auth/me', 200, ok(userJson(permissions: ['manage-sales'])));
    await pumpApp(tester);
    expect(find.byKey(const Key('dashboard-shift')), findsNothing);
    expect(h.backend.calls('GET', '/shifts/current'), isEmpty);
  });

  test('categories per direction match the backend rules', () {
    expect(CashCategory.of(CashDirection.cashIn).map((c) => c.apiValue), ['income', 'deposit', 'other']);
    expect(CashCategory.of(CashDirection.cashOut).map((c) => c.apiValue), ['expense', 'withdrawal', 'other']);
    expect(CashCategory.labelOf('out', 'other'), 'Lainnya');
  });
}
