import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/network/api_client.dart';
import 'package:kagoem_pos_mobile/core/storage/session_store.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/data/datasources/catalog_remote_datasource.dart';
import 'package:kagoem_pos_mobile/data/repositories/catalog_repository_impl.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> productJson({
  int id = 1,
  String name = 'Kopi Susu',
  String sku = 'KOPI-01',
  String? barcode = '8991234567890',
  num price = 15000,
  int stock = 8,
}) =>
    {
      'id': id,
      'barcode': barcode,
      'sku': sku,
      'name': name,
      'category_id': 2,
      'category_name': 'Minuman',
      'brand_id': 1,
      'brand_name': 'Kagoem',
      'unit_id': 1,
      'unit_name': 'pcs',
      'cost_price': 9000.0,
      'price': price,
      'stock': stock,
      'min_stock': 2,
      'tax_percentage': 11.0,
      'discount_percentage': 12.5,
      'image_url': null,
      'is_active': true,
      'is_low_stock': false,
      'created_at': '2026-09-01T10:00:00+07:00',
    };

Map<String, dynamic> page(List<Map<String, dynamic>> items, {int current = 1, int last = 1}) =>
    ok(items, meta: {'current_page': current, 'last_page': last, 'per_page': 50, 'total': items.length});

void main() {
  late FakeBackend backend;
  late ApiClient api;
  late CatalogRepositoryImpl repo;

  setUp(() {
    backend = FakeBackend();
    api = ApiClient(
      baseUrl: 'http://pos.test/api/v1',
      session: SessionStore(InMemoryKeyValueStore()),
      adapter: backend,
      retryDelay: Duration.zero,
    );
    repo = CatalogRepositoryImpl(CatalogRemoteDataSource(api));
  });

  tearDown(() => api.dispose());

  test('product list: active only, query forwarded, ProductResource parsed exactly', () async {
    backend.reply('GET', '/products', 200, page([productJson()], last: 3));

    final result = await repo.products(search: ' kopi ', categoryId: 2, page: 1);

    expect(backend.requests.single.uri.queryParameters, {
      'search': 'kopi',
      'category_id': '2',
      'is_active': '1',
      'sort': 'name',
      'direction': 'asc',
      'page': '1',
      'per_page': '50',
    });
    final p = result.items.single;
    expect(p.name, 'Kopi Susu');
    expect(p.price, Money.rupiah(15000));
    expect(p.taxHundredths, 1100);
    expect(p.discountHundredths, 1250);
    expect(p.categoryName, 'Minuman');
    expect(p.unitName, 'pcs');
    expect(result.meta.hasMore, isTrue);
  });

  test('barcode lookup returns the exact match only', () async {
    backend.reply('GET', '/products', 200, page([
      productJson(id: 1, barcode: '89912345678901', sku: 'A'),
      productJson(id: 2, barcode: '8991234567890', sku: 'B'),
    ]));

    final found = await repo.findByCode('8991234567890');

    expect(found?.id, 2);
    expect(backend.requests.single.uri.queryParameters['search'], '8991234567890');
  });

  test('barcode lookup: no exact match → null (product not found)', () async {
    backend.reply('GET', '/products', 200, page([productJson(barcode: '8991234567890')]));
    expect(await repo.findByCode('899123'), isNull);
  });

  test('categories are fetched once per repository (tenant)', () async {
    backend.reply('GET', '/categories', 200, page([
      {'id': 2, 'name': 'Minuman', 'slug': 'minuman', 'is_active': true},
    ]));

    expect((await repo.categories()).single.name, 'Minuman');
    await repo.categories();
    expect(backend.calls('GET', '/categories'), hasLength(1));
  });
}
