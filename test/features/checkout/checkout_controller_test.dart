import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/domain/entities/product.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/cart_controller.dart';
import 'package:kagoem_pos_mobile/features/checkout/application/checkout_controller.dart';
import 'package:kagoem_pos_mobile/features/outlet/outlet_controller.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/test_app.dart';

const kopi = Product(id: 1, name: 'Kopi', sku: 'K1', price: Money.minor(1000000), stock: 10, taxHundredths: 1100);

/// SaleResource as the backend returns it for 2 × Kopi (tax 11%).
Map<String, dynamic> saleJson({
  int id = 55,
  String invoice = 'TX-261003-00001',
  String? clientReference,
  bool withClientReferenceKey = true,
  num paid = 25000,
  String method = 'cash',
}) =>
    {
      'id': id,
      'invoice_number': invoice,
      if (withClientReferenceKey) 'client_reference': clientReference,
      'branch_id': 3,
      'branch_name': 'Toko Pusat',
      'customer': null,
      'cashier_name': 'Siti Kasir',
      'items': [
        {
          'id': 1,
          'product_id': 1,
          'product_name': 'Kopi',
          'qty': 2,
          'price': 10000.0,
          'discount_amount': 0.0,
          'tax_amount': 2200.0,
          'subtotal': 22200.0,
        },
      ],
      'subtotal': 20000.0,
      'discount_amount': 0.0,
      'tax_amount': 2200.0,
      'grand_total': 22200.0,
      'paid_amount': paid,
      'change_amount': paid - 22200,
      'payment_method': method,
      'status': 'paid',
      'created_at': '2026-10-03T10:20:00+07:00',
    };

Future<void> waitUntil(ProviderContainer c, bool Function() predicate) async {
  for (var i = 0; i < 200 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(predicate(), isTrue, reason: 'condition not reached');
}

void main() {
  late TestHarness h;
  late ProviderContainer c;

  Future<void> start({Map<String, dynamic>? user, List<Map<String, dynamic>>? branches}) async {
    h = TestHarness();
    await h.session.saveToken('5|tok');
    h.backend.reply('GET', '/auth/me', 200, ok(user ?? userJson()));
    h.backend.reply('GET', '/tenants', 200, ok([tenantJson()]));
    h.backend.reply('GET', '/branches', 200, ok(branches ?? [], meta: {'current_page': 1, 'last_page': 1, 'per_page': 100, 'total': 0}));
    c = h.container();
    // Keep the session alive and wait until ready.
    c.listen(sessionControllerProvider, (_, _) {});
    await waitUntil(c, () => c.read(sessionControllerProvider).status == SessionStatus.ready);
    c.listen(cartControllerProvider, (_, _) {});
    c.listen(checkoutControllerProvider, (_, _) {});
    c.listen(outletControllerProvider, (_, _) {});
    await c.read(outletControllerProvider.future);
    c.read(cartControllerProvider.notifier).add(kopi, qty: 2);
  }

  tearDown(() => c.dispose());

  CheckoutController checkout() => c.read(checkoutControllerProvider.notifier);
  CheckoutState state() => c.read(checkoutControllerProvider);

  group('cash checkout', () {
    setUp(() => start());

    test('sends only ids, qty, method and paid amount with an Idempotency-Key; shows server numbers', () async {
      h.backend.reply('POST', '/sales', 201, ok(saleJson(), message: 'Transaksi berhasil disimpan'));

      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(25000);
      await checkout().submit();

      final request = h.backend.calls('POST', '/sales').single;
      expect(request.data, {
        'branch_id': null, // home branch: the server decides
        'customer_id': null,
        'items': [
          {'product_id': 1, 'qty': 2},
        ],
        'payment_method': 'cash',
        'paid_amount': 25000,
      });
      expect(request.headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f-]{36}$')));

      expect(state().phase, CheckoutPhase.success);
      expect(state().sale!.invoiceNumber, 'TX-261003-00001');
      expect(state().sale!.change, Money.rupiah(2800));
      expect(c.read(cartControllerProvider).isEmpty, isTrue);
    });

    test('cash below the total is blocked before any request', () async {
      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(20000); // total is 22.200

      expect(checkout().blockingReason(c.read(cartControllerProvider), c.read(outletControllerProvider).value),
          'Uang diterima kurang dari total.');
      await checkout().submit();
      expect(h.backend.calls('POST', '/sales'), isEmpty);
      expect(state().failure?.message, 'Uang diterima kurang dari total.');
    });

    test('a payment method is required', () async {
      await checkout().submit();
      expect(h.backend.calls('POST', '/sales'), isEmpty);
      expect(state().failure?.message, 'Pilih metode pembayaran.');
    });

    test('double tap sends exactly one request', () async {
      h.backend.on('POST', '/sales', (_) => (status: 201, body: ok(saleJson())));
      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(25000);

      // Two taps while the first request is in flight.
      final first = checkout().submit();
      expect(state().isSubmitting, isTrue);
      final second = checkout().submit();
      await Future.wait([first, second]);

      expect(h.backend.calls('POST', '/sales'), hasLength(1));
      expect(state().phase, CheckoutPhase.success);
    });

    test('server stock rejection keeps the cart and shows the backend message', () async {
      h.backend.reply('POST', '/sales', 422, validationError({
        'items': ['Stok Kopi tidak mencukupi (tersisa 1).'],
      }));
      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(25000);
      await checkout().submit();

      expect(state().phase, CheckoutPhase.editing);
      expect(state().failure?.message, 'Stok Kopi tidak mencukupi (tersisa 1).');
      expect(c.read(cartControllerProvider).itemCount, 2);
    });

    test('server error is not shown as success and keeps the cart', () async {
      h.backend.reply('POST', '/sales', 500, {'message': 'Server Error'});
      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(25000);
      await checkout().submit();

      expect(state().phase, CheckoutPhase.editing);
      expect(state().failure?.message, 'Terjadi kesalahan pada server. Silakan coba lagi.');
      expect(c.read(cartControllerProvider).isNotEmpty, isTrue);
    });
  });

  group('non-cash', () {
    setUp(() => start());

    test('paid amount is the total rounded up; replayed sale (200) is reported', () async {
      h.backend.reply('POST', '/sales', 200, ok(saleJson(method: 'qris', paid: 22200)));
      checkout().setPaymentMethod(PaymentMethod.qris);
      await checkout().submit();

      final body = h.backend.calls('POST', '/sales').single.data as Map;
      expect(body['payment_method'], 'qris');
      expect(body['paid_amount'], 22200);
      expect(state().replayed, isTrue);
    });
  });

  group('timeout / unknown outcome', () {
    setUp(() => start());

    Future<String> timeoutOnce() async {
      h.backend.failures['POST /sales'] = DioExceptionType.receiveTimeout;
      checkout().setPaymentMethod(PaymentMethod.cash);
      checkout().setCashReceived(25000);
      await checkout().submit();
      return h.backend.calls('POST', '/sales').single.headers['Idempotency-Key'] as String;
    }

    test('sale found among recent sales → success without sending again', () async {
      h.backend.on('GET', '/sales', (_) => (status: 200, body: ok([])));
      final key = await timeoutOnce();
      h.backend.on('GET', '/sales', (_) => (status: 200, body: ok([saleJson(clientReference: key)])));

      // First check happened right after the timeout (nothing yet); check again.
      expect(state().phase, CheckoutPhase.unknown);
      await checkout().checkRecent();

      expect(state().phase, CheckoutPhase.success);
      expect(state().sale!.clientReference, key);
      expect(h.backend.calls('POST', '/sales'), hasLength(1));
      expect(c.read(cartControllerProvider).isEmpty, isTrue);
    });

    test('not found on an idempotent backend → resend reuses the same key', () async {
      h.backend.reply('GET', '/sales', 200, ok([saleJson(id: 9, invoice: 'TX-OTHER', clientReference: 'someone-else')]));
      final key = await timeoutOnce();

      expect(state().phase, CheckoutPhase.unknown);
      expect(state().recent!.backendSupportsIdempotency, isTrue);
      expect(c.read(cartControllerProvider).isNotEmpty, isTrue, reason: 'cart kept until confirmed');

      h.backend.failures.clear();
      h.backend.reply('POST', '/sales', 200, ok(saleJson(clientReference: key)));
      await checkout().resend();

      final keys = h.backend.calls('POST', '/sales').map((r) => r.headers['Idempotency-Key']).toList();
      expect(keys, [key, key]);
      expect(state().phase, CheckoutPhase.success);
    });

    test('old backend without idempotency → cashier must verify; nothing is re-sent automatically', () async {
      h.backend.reply('GET', '/sales', 200, ok([saleJson(withClientReferenceKey: false)]));
      await timeoutOnce();

      expect(state().phase, CheckoutPhase.unknown);
      expect(state().recent!.backendSupportsIdempotency, isFalse);
      expect(h.backend.calls('POST', '/sales'), hasLength(1));

      checkout().confirmRecorded(state().recent!.sales.first);
      expect(state().phase, CheckoutPhase.success);
    });

    test('same checkout submitted again after returning keeps the key; a changed cart gets a new one', () async {
      h.backend.reply('GET', '/sales', 200, ok([]));
      final key = await timeoutOnce();
      checkout().dismissUnknown();

      h.backend.failures.clear();
      h.backend.reply('POST', '/sales', 422, validationError({'items': ['Stok Kopi tidak mencukupi (tersisa 1).']}));
      await checkout().submit();
      expect(h.backend.calls('POST', '/sales').last.headers['Idempotency-Key'], key);

      c.read(cartControllerProvider.notifier).decrement(1);
      checkout().setCashReceived(25000);
      await checkout().submit();
      expect(h.backend.calls('POST', '/sales').last.headers['Idempotency-Key'], isNot(key));
    });
  });

  group('outlet', () {
    test('cashier without a home branch must pick one when the tenant has several', () async {
      await start(
        user: userJson(branchId: null),
        branches: [
          {'id': 3, 'name': 'Pusat', 'code': 'P'},
          {'id': 4, 'name': 'Cabang 2', 'code': 'C2'},
        ],
      );
      checkout().setPaymentMethod(PaymentMethod.qris);
      final outlet = c.read(outletControllerProvider).value!;
      expect(outlet.needsSelection, isTrue);
      expect(checkout().blockingReason(c.read(cartControllerProvider), outlet), 'Pilih outlet terlebih dahulu.');

      await c.read(outletControllerProvider.notifier).select(outlet.options.last);
      h.backend.reply('POST', '/sales', 201, ok(saleJson(method: 'qris', paid: 22200)));
      await checkout().submit();
      expect((h.backend.calls('POST', '/sales').single.data as Map)['branch_id'], 4);
      expect(h.session.branchId, 4);
    });

    test('a single branch is selected automatically', () async {
      await start(user: userJson(branchId: null), branches: [
        {'id': 3, 'name': 'Pusat', 'code': 'P'},
      ]);
      final outlet = c.read(outletControllerProvider).value!;
      expect(outlet.selected?.id, 3);
      expect(outlet.requestBranchId, 3);
    });
  });

  test('quick cash suggestions start with the exact amount', () {
    expect(quickCashOptions(22200), [22200, 25000, 30000, 40000, 50000]);
    expect(quickCashOptions(50000), [50000, 60000, 100000]); // 60.000 = 3 × Rp 20.000
    expect(quickCashOptions(0), isEmpty);
  });
}
