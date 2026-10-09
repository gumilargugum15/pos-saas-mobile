import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../data/catalog_repository_test.dart' show page;
import '../helpers/fake_backend.dart';
import '../helpers/test_app.dart';

/// Admin-only backend endpoints (docs/CASHIER_PERMISSION.md §4). The
/// cashier app must never call them, whatever the user's permissions.
const adminEndpoints = [
  "'/users",
  "'/roles",
  "'/permissions",
  "'/provisioning",
  "'/purchases",
  "'/suppliers",
  "'/stock-movements",
  "'/reports",
  "'/warehouses",
  '/refund',
];

void main() {
  group('admin-only features are blocked', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (path: f.path, code: f.readAsStringSync()))
        .toList();

    test('no admin endpoint is referenced anywhere in the app', () {
      for (final s in sources) {
        for (final endpoint in adminEndpoints) {
          expect(s.code.contains(endpoint), isFalse, reason: '${s.path} references $endpoint');
        }
      }
    });

    test('the only writes are session, checkout, customers, cash drawer and product create/edit', () {
      final writes = RegExp(r"_api\.(post|put)\(\s*'([^']+)'");
      final found = {
        for (final s in sources)
          for (final m in writes.allMatches(s.code)) '${m.group(1)!.toUpperCase()} ${m.group(2)}',
      };
      expect(found, {
        'POST /auth/login',
        'POST /auth/logout',
        'POST /sales',
        'POST /customers',
        // Drawer (operate-cash-drawer): open/close own shift, cash in/out.
        'POST /shifts',
        r'POST /shifts/$shiftId/close',
        'POST /cash-transactions',
        // Product edit (manage-products, Admin / Owner): multipart + _method=PUT.
        r'POST /products/$productId',
        'POST /products',
      });
    });

    test('no admin screens are routed', () {
      final router = File('lib/routing/app_router.dart').readAsStringSync();
      for (final path in ['users', 'roles', 'permissions', 'settings', 'reports', 'tenants']) {
        expect(router.contains("path: '$path'"), isFalse, reason: 'route $path');
      }
    });
  });

  group('customer creation follows manage-customers', () {
    late TestHarness h;

    Future<void> openCustomers(WidgetTester tester, List<String> permissions) async {
      h = TestHarness();
      await h.session.saveToken('5|tok');
      h.backend.reply('GET', '/auth/me', 200, ok(userJson(permissions: permissions)));
      h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
      h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
      h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
      h.backend.reply('GET', '/customers', 200, page([
        {'id': 7, 'name': 'Budi', 'phone': '0812', 'email': null, 'address': null, 'is_active': true},
      ]));
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()));
      await tester.pumpAndSettle();

      final menu = find.widgetWithText(InkWell, 'Pelanggan');
      await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Budi'), findsOneWidget);
    }

    testWidgets('Kasir (manage-sales only) can look up but not add customers', (tester) async {
      await openCustomers(tester, ['manage-sales', 'operate-cash-drawer']);
      expect(find.text('Tambah'), findsNothing);
    });

    testWidgets('a user with manage-customers can add customers', (tester) async {
      await openCustomers(tester, ['manage-sales', 'manage-customers']);
      expect(find.text('Tambah'), findsOneWidget);
    });
  });
}
