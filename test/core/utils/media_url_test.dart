import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/utils/media_url.dart';

void main() {
  const prod = 'https://pos.kagoemdigital.my.id/api/v1';
  const emulator = 'http://10.0.2.2:8001/api/v1';

  test('local backend (APP_URL=localhost) → reachable from the emulator', () {
    expect(
      MediaUrl.resolve('http://localhost:8001/storage/products/a.png', emulator),
      'http://10.0.2.2:8001/storage/products/a.png',
    );
  });

  test('http image from an HTTPS API (proxy without trusted proxies) → https', () {
    expect(
      MediaUrl.resolve('http://pos.kagoemdigital.my.id/storage/products/a.png', prod),
      'https://pos.kagoemdigital.my.id/storage/products/a.png',
    );
  });

  test('wrong local APP_URL leaking to production → production host, default port', () {
    expect(
      MediaUrl.resolve('http://127.0.0.1:8000/storage/products/a.png?v=2', prod),
      'https://pos.kagoemdigital.my.id/storage/products/a.png?v=2',
    );
  });

  test('already-correct URLs are unchanged', () {
    const url = 'https://pos.kagoemdigital.my.id/storage/products/a.png';
    expect(MediaUrl.resolve(url, prod), url);
  });

  test('other hosts (CDN) are left alone', () {
    const url = 'https://cdn.example.com/img/a.png';
    expect(MediaUrl.resolve(url, prod), url);
  });

  test('missing or invalid values → no image', () {
    expect(MediaUrl.resolve(null, prod), isNull);
    expect(MediaUrl.resolve('', prod), isNull);
    expect(MediaUrl.resolve('products/a.png', prod), isNull);
  });
}
