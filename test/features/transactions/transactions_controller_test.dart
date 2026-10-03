import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/transactions/application/transactions_controller.dart';

import '../../data/catalog_repository_test.dart' show page;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';
import '../checkout/checkout_controller_test.dart' show saleJson, waitUntil;

void main() {
  group('date presets', () {
    final now = DateTime(2026, 10, 3, 15, 30);

    test('today, 7 and 30 days are inclusive whole days', () {
      expect(const TransactionsFilter().dateRange(now), (DateTime(2026, 10, 3), DateTime(2026, 10, 3)));
      expect(const TransactionsFilter(datePreset: DatePreset.last7).dateRange(now),
          (DateTime(2026, 9, 27), DateTime(2026, 10, 3)));
      expect(const TransactionsFilter(datePreset: DatePreset.last30).dateRange(now),
          (DateTime(2026, 9, 4), DateTime(2026, 10, 3)));
    });

    test('all = no date filter; custom uses the picked range', () {
      expect(const TransactionsFilter(datePreset: DatePreset.all).dateRange(now), (null, null));
      final range = DateTimeRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31));
      expect(TransactionsFilter(datePreset: DatePreset.custom, customRange: range).dateRange(now),
          (DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
    });
  });

  group('history query', () {
    late TestHarness h;
    late ProviderContainer c;

    Future<void> start({int? homeBranch}) async {
      h = TestHarness();
      await h.session.saveToken('5|tok');
      h.backend.reply('GET', '/auth/me', 200, ok(userJson(branchId: homeBranch)));
      h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
      h.backend.reply('GET', '/branches', 200, page([
        {'id': 4, 'name': 'Cabang 2', 'code': 'C2'},
      ]));
      h.backend.reply('GET', '/sales', 200, page([saleJson()]));
      c = h.container();
      c.listen(sessionControllerProvider, (_, _) {});
      await waitUntil(c, () => c.read(sessionControllerProvider).status == SessionStatus.ready);
      c.listen(transactionsControllerProvider, (_, _) {});
      await waitUntil(c, () => !c.read(transactionsControllerProvider).isLoading);
    }

    tearDown(() => c.dispose());

    test('defaults to today; a home-branch cashier lets the server scope the branch', () async {
      await start(homeBranch: 3);
      final q = h.backend.calls('GET', '/sales').single.uri.queryParameters;
      final today = DateTime.now();
      final ymd = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      expect(q['date_from'], ymd);
      expect(q['date_to'], ymd);
      expect(q.containsKey('branch_id'), isFalse);
      expect(c.read(transactionsControllerProvider).items.single.invoiceNumber, 'TX-261003-00001');
    });

    test('a cashier without home branch sees the chosen outlet', () async {
      await start();
      expect(h.backend.calls('GET', '/sales').single.uri.queryParameters['branch_id'], '4');
    });

    test('changing filters reloads with the new query', () async {
      await start(homeBranch: 3);
      final controller = c.read(transactionsControllerProvider.notifier);
      controller.setFilter(const TransactionsFilter(
        search: 'TX-26',
        datePreset: DatePreset.all,
        paymentMethod: PaymentMethod.cash,
        status: SaleStatus.paid,
      ));
      await waitUntil(c, () => h.backend.calls('GET', '/sales').length == 2 && !c.read(transactionsControllerProvider).isLoading);

      final q = h.backend.calls('GET', '/sales').last.uri.queryParameters;
      expect(q['search'], 'TX-26');
      expect(q['payment_method'], 'cash');
      expect(q['status'], 'paid');
      expect(q.containsKey('date_from'), isFalse);
    });
  });
}
