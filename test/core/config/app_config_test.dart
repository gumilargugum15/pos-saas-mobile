import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/config/app_config.dart';

void main() {
  test('parses a development config and strips trailing slashes', () {
    final c = AppConfig.parse(envName: 'development', baseUrl: 'http://192.168.1.10:8001/api/v1/');
    expect(c.environment, AppEnvironment.development);
    expect(c.apiBaseUrl, 'http://192.168.1.10:8001/api/v1');
    expect(c.isProduction, isFalse);
  });

  test('requires a base URL', () {
    expect(() => AppConfig.parse(envName: 'development', baseUrl: ''), throwsA(isA<ConfigException>()));
    expect(() => AppConfig.parse(envName: 'development', baseUrl: 'not a url'), throwsA(isA<ConfigException>()));
  });

  test('staging and production must use https', () {
    expect(() => AppConfig.parse(envName: 'production', baseUrl: 'http://pos.example.com/api/v1'),
        throwsA(isA<ConfigException>()));
    expect(AppConfig.parse(envName: 'production', baseUrl: 'https://pos.example.com/api/v1').isProduction, isTrue);
  });

  test('rejects unknown environments', () {
    expect(() => AppConfig.parse(envName: 'prod', baseUrl: 'https://x.y'), throwsA(isA<ConfigException>()));
  });
}
