import 'dart:io';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';
import 'package:kagoem_pos_mobile/domain/entities/tenant.dart';
import 'package:kagoem_pos_mobile/domain/entities/user.dart';
import 'package:kagoem_pos_mobile/domain/usecases/cashier_access.dart';
import 'package:kagoem_pos_mobile/features/products/presentation/product_edit_page.dart';

import '../../data/catalog_repository_test.dart' show page, productJson;
import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

Map<String, String> fields(Object? data) => {for (final e in (data as FormData).fields) e.key: e.value};

void main() {
  group('who may edit', () {
    User user(List<String> permissions) => User(id: 1, name: 'A', email: 'a@b.c', permissions: permissions);

    test('Admin / Owner (manage-products) yes; Kasir no', () {
      expect(CashierCapabilities(user(['manage-sales', 'manage-products'])).canEditProducts, isTrue);
      expect(CashierCapabilities(user(['manage-sales', 'operate-cash-drawer'])).canEditProducts, isFalse);
    });

    test('not when the tenant plan lacks the products module (backend would answer 403)', () {
      const starter = Tenant(id: 1, name: 'T', modules: ['sales']);
      expect(CashierCapabilities(user(['manage-products']), tenant: starter).canEditProducts, isFalse);
      const all = Tenant(id: 1, name: 'T');
      expect(CashierCapabilities(user(['manage-products']), tenant: all).canEditProducts, isTrue);
    });
  });

  group('edit flow', () {
    late TestHarness h;
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kagoem-edit');
      h = TestHarness();
      await h.session.saveToken('5|tok');
      h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
      h.backend.reply('GET', '/settings', 200, ok(<String, dynamic>{}));
      h.backend.reply('GET', '/dashboard', 200, ok({'stats': <String, dynamic>{}}));
      h.backend.reply('GET', '/categories', 200, page([
        {'id': 2, 'name': 'Minuman', 'slug': 'minuman', 'is_active': true},
      ]));
      h.backend.reply('GET', '/brands', 200, page([
        {'id': 1, 'name': 'Kagoem'},
      ]));
      h.backend.reply('GET', '/units', 200, page([
        {'id': 1, 'name': 'pcs'},
      ]));
      final kopi = productJson(id: 1, name: 'Kopi Susu', price: 10000, stock: 8);
      h.backend.reply('GET', '/products', 200, page([kopi]));
      h.backend.reply('GET', '/products/1', 200, ok(kopi));
    });

    tearDown(() => tmp.delete(recursive: true));

    Future<void> openEdit(WidgetTester tester, List<String> permissions) async {
      h.backend.reply('GET', '/auth/me', 200, ok(userJson(permissions: permissions)));
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...h.overrides,
          productPhotoPickerProvider.overrideWithValue((_) async {
            final f = File('${tmp.path}/foto.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
            return f.path;
          }),
        ],
        retry: (_, _) => null,
        child: const KagoemPosApp(),
      ));
      await tester.pumpAndSettle();
      final menu = find.widgetWithText(InkWell, 'Produk');
      await tester.scrollUntilVisible(menu, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopi Susu'));
      await tester.pumpAndSettle();
    }

    testWidgets('a Kasir sees no edit button', (tester) async {
      await openEdit(tester, ['manage-sales', 'operate-cash-drawer']);
      expect(find.byKey(const Key('product-edit')), findsNothing);
    });

    testWidgets('Owner edits price, stock and photo; only changes are sent, as multipart PUT', (tester) async {
      h.backend.on('POST', '/products/1', (r) {
        final f = fields(r.data);
        return (
          status: 200,
          body: ok(productJson(id: 1, name: 'Kopi Susu', price: num.parse(f['price']!), stock: int.parse(f['stock']!))),
        );
      });
      await openEdit(tester, ['manage-sales', 'manage-products']);

      await tester.tap(find.byKey(const Key('product-edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Produk'), findsOneWidget);
      expect(find.text('10.000'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('edit-price')), '12000');
      await tester.enterText(find.byKey(const Key('edit-stock')), '20');
      await tester.tap(find.byKey(const Key('photo-gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit-save')));
      // Attaching the photo reads a real file: give real I/O time to finish.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();

      final request = h.backend.calls('POST', '/products/1').single;
      expect(fields(request.data), {'_method': 'PUT', 'price': '12000', 'stock': '20'});
      final files = (request.data as FormData).files;
      expect(files.single.key, 'image');
      expect(files.single.value.filename, 'foto.jpg');

      expect(find.text('Produk Kopi Susu diperbarui.'), findsOneWidget);
      expect(find.text('Edit Produk'), findsNothing);
    });

    testWidgets('server rule (SKU already used) shows next to the field', (tester) async {
      h.backend.reply('POST', '/products/1', 422, validationError({
        'sku': ['The sku has already been taken.'],
      }));
      await openEdit(tester, ['manage-sales', 'manage-products']);
      await tester.tap(find.byKey(const Key('product-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit-sku')), 'TEH-01');
      await tester.tap(find.byKey(const Key('edit-save')));
      await tester.pumpAndSettle();

      expect(find.text('SKU sudah dipakai produk lain.'), findsOneWidget);
      expect(fields(h.backend.calls('POST', '/products/1').single.data), {'_method': 'PUT', 'sku': 'TEH-01'});
    });

    testWidgets('invalid input never reaches the server', (tester) async {
      await openEdit(tester, ['manage-sales', 'manage-products']);
      await tester.tap(find.byKey(const Key('product-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit-name')), '');
      await tester.enterText(find.byKey(const Key('edit-discount')), '150');
      await tester.tap(find.byKey(const Key('edit-save')));
      await tester.pumpAndSettle();

      expect(find.text('Wajib diisi.'), findsOneWidget);
      expect(find.text('Maksimal 100.'), findsOneWidget);
      expect(h.backend.calls('POST', '/products/1'), isEmpty);
    });
  });
}
