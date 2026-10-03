import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/error/app_failure.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/data/repositories/sales_repository_impl.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/domain/repositories/sales_repository.dart';

import '../features/checkout/checkout_controller_test.dart' show saleJson;
import '../helpers/fake_backend.dart';
import 'catalog_repository_test.dart' show page;

void main() {
  late FakeBackend backend;
  late ApiClient api;
  late SalesRepositoryImpl repo;

  setUp(() {
    backend = FakeBackend();
    api = ApiClient(
      baseUrl: 'http://pos.test/api/v1',
      session: SessionStore(InMemoryKeyValueStore()),
      adapter: backend,
      retryDelay: Duration.zero,
    );
    repo = SalesRepositoryImpl(api);
  });

  tearDown(() => api.dispose());

  group('checkout', () {
    const request = CheckoutRequest(
      items: [
        {'product_id': 1, 'qty': 2},
      ],
      paymentMethod: PaymentMethod.eWallet,
      paidRupiah: 22200,
      customerId: 7,
      branchId: 3,
    );

    test('201 → new sale; SaleResource parsed exactly', () async {
      backend.reply('POST', '/sales', 201, ok(saleJson(clientReference: 'k-1')));

      final result = await repo.checkout(request, idempotencyKey: 'k-1');

      final sent = backend.requests.single;
      expect(sent.headers['Idempotency-Key'], 'k-1');
      expect(sent.data, {
        'branch_id': 3,
        'customer_id': 7,
        'items': [
          {'product_id': 1, 'qty': 2},
        ],
        'payment_method': 'e_wallet',
        'paid_amount': 22200,
      });
      expect(result.replayed, isFalse);
      final sale = result.sale;
      expect(sale.invoiceNumber, 'TX-261003-00001');
      expect(sale.clientReference, 'k-1');
      expect(sale.grandTotal, Money.rupiah(22200));
      expect(sale.tax, Money.rupiah(2200));
      expect(sale.items.single.productName, 'Kopi');
      expect(sale.customerLabel, 'Walk-in');
      expect(sale.status, SaleStatus.paid);
      expect(sale.createdAt, isNotNull);
    });

    test('200 → replay of an existing sale', () async {
      backend.reply('POST', '/sales', 200, ok(saleJson()));
      expect((await repo.checkout(request, idempotencyKey: 'k-1')).replayed, isTrue);
    });

    test('fingerprint changes with anything that changes the sale', () {
      const other = CheckoutRequest(
        items: [
          {'product_id': 1, 'qty': 3},
        ],
        paymentMethod: PaymentMethod.eWallet,
        paidRupiah: 22200,
        customerId: 7,
        branchId: 3,
      );
      expect(request.fingerprint, isNot(other.fingerprint));
      expect(request.fingerprint, request.fingerprint);
    });
  });

  group('history', () {
    test('filters map to the backend query (dates as YYYY-MM-DD, newest first)', () async {
      backend.reply('GET', '/sales', 200, page([saleJson()]));

      await repo.list(
        SalesQuery(
          search: ' TX-2610 ',
          status: SaleStatus.refunded,
          paymentMethod: PaymentMethod.qris,
          dateFrom: DateTime(2026, 9, 1),
          dateTo: DateTime(2026, 10, 3),
          branchId: 4,
        ),
        page: 2,
      );

      expect(backend.requests.single.uri.queryParameters, {
        'search': 'TX-2610',
        'status': 'refunded',
        'payment_method': 'qris',
        'date_from': '2026-09-01',
        'date_to': '2026-10-03',
        'branch_id': '4',
        'sort': 'created_at',
        'direction': 'desc',
        'page': '2',
        'per_page': '20',
      });
    });

    test('unknown payment methods from the backend still display', () {
      expect(PaymentMethod.labelOf('voucher_toko'), 'voucher toko');
      expect(PaymentMethod.labelOf('credit_card'), 'Kartu Kredit');
    });

    test('recent(): detects whether the backend supports idempotency', () async {
      backend.reply('GET', '/sales', 200, ok([saleJson(clientReference: null)]));
      expect((await repo.recent()).backendSupportsIdempotency, isTrue);

      backend.reply('GET', '/sales', 200, ok([saleJson(withClientReferenceKey: false)]));
      expect((await repo.recent()).backendSupportsIdempotency, isFalse);
    });

    test('detail: cross-tenant / missing id → friendly not-found', () async {
      backend.reply('GET', '/sales/999', 404, {'message': 'No query results for model [App\\Models\\Sale] 999'});
      await expectLater(
        repo.detail(999),
        throwsA(isA<AppFailure>().having((f) => f.message, 'message', 'Data tidak ditemukan.')),
      );
    });
  });

  group('customers & branches', () {
    test('customer search asks for active customers only', () async {
      backend.reply('GET', '/customers', 200, page([
        {'id': 7, 'name': 'Budi', 'phone': '0812', 'email': null, 'address': null, 'is_active': true},
      ]));

      final result = await repo.customers(search: 'bud');

      expect(result.items.single.name, 'Budi');
      expect(backend.requests.single.uri.queryParameters['is_active'], '1');
      expect(backend.requests.single.uri.queryParameters['search'], 'bud');
    });

    test('create customer sends trimmed fields, blanks as null', () async {
      backend.reply('POST', '/customers', 201, ok({'id': 8, 'name': 'Sari', 'phone': null, 'email': null, 'address': null}));

      await repo.createCustomer(name: '  Sari ', phone: ' ', email: '');

      expect(backend.requests.single.data, {'name': 'Sari', 'phone': null, 'email': null, 'address': null});
    });

    test('create customer without permission → friendly 403', () async {
      backend.reply('POST', '/customers', 403, {'success': false, 'message': 'This action is unauthorized.', 'errors': []});
      await expectLater(
        repo.createCustomer(name: 'X'),
        throwsA(isA<AppFailure>().having((f) => f.message, 'message', 'Anda tidak memiliki akses untuk fitur ini.')),
      );
    });

    test('branches: active ones', () async {
      backend.reply('GET', '/branches', 200, page([
        {'id': 3, 'name': 'Pusat', 'code': 'P', 'phone': null, 'address': 'Jl. Merdeka 1', 'is_active': true},
      ]));
      final branches = await repo.branches();
      expect(branches.single.address, 'Jl. Merdeka 1');
      expect(backend.requests.single.uri.queryParameters['is_active'], '1');
    });
  });
}
