import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/app.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, retry: (_, _) => null, child: const KagoemPosApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillLogin(WidgetTester tester, {String email = 'siti@toko.id', String password = 'rahasia'}) async {
    await tester.enterText(find.byKey(const Key('login-email')), email);
    await tester.enterText(find.byKey(const Key('login-password')), password);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('empty form shows validation without calling the API', (tester) async {
    await pumpApp(tester);
    expect(find.text('MASUK'), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Email wajib diisi.'), findsOneWidget);
    expect(find.text('Password wajib diisi.'), findsOneWidget);
    expect(h.backend.calls('POST', '/auth/login'), isEmpty);
  });

  testWidgets('wrong credentials show the backend message under the email field', (tester) async {
    h.backend.reply('POST', '/auth/login', 422, validationError({
      'email': ['Email atau password salah.'],
    }));
    await pumpApp(tester);

    await fillLogin(tester, password: 'salah');

    expect(find.text('Email atau password salah.'), findsOneWidget);
    expect(find.text('MASUK'), findsOneWidget);
  });

  testWidgets('cashier logs in and lands on home with name and outlet', (tester) async {
    h.backend.reply('POST', '/auth/login', 200, ok({'user': userJson(), 'token': '5|tok'}));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    await pumpApp(tester);

    await fillLogin(tester);

    expect(find.text('Kagoem'), findsOneWidget); // logo in the app bar
    expect(find.text('Siti Kasir'), findsOneWidget);
    expect(find.text('Toko ABC'), findsOneWidget);
    expect(find.text('Toko Pusat'), findsOneWidget);
  });

  testWidgets('user without cashier permission sees Access Denied and can log out', (tester) async {
    h.backend.reply('POST', '/auth/login', 200, ok({
      'user': userJson(roles: ['Gudang'], permissions: ['manage-inventory']),
      'token': '5|tok',
    }));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('POST', '/auth/logout', 200, ok(null));
    await pumpApp(tester);

    await fillLogin(tester);
    expect(find.text('Akses Ditolak'), findsOneWidget);
    expect(find.textContaining('tidak memiliki izin kasir'), findsOneWidget);

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('MASUK'), findsOneWidget);
    expect(h.store.values, isEmpty);
  });

  testWidgets('multi-tenant user picks a tenant first', (tester) async {
    h.backend.reply('POST', '/auth/login', 200, ok({'user': userJson(), 'token': '5|tok'}));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson(id: 1), tenantJson(id: 2, name: 'Toko XYZ')]));
    await pumpApp(tester);

    await fillLogin(tester);
    expect(find.text('Pilih Perusahaan'), findsOneWidget);

    await tester.tap(find.text('Toko XYZ'));
    await tester.pumpAndSettle();
    expect(find.text('Toko XYZ'), findsOneWidget);
    expect(find.text('Siti Kasir'), findsOneWidget);
    expect(h.session.tenantId, 2);
  });
}
