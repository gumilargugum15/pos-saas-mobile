import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/error/app_failure.dart';
import 'package:kagoem_pos_mobile/core/network/error_mapper.dart';

void main() {
  group('mapErrorResponse', () {
    test('401 becomes a session-expired message', () {
      final f = mapErrorResponse(401, {'success': false, 'message': 'Unauthenticated.', 'errors': []});
      expect(f.kind, FailureKind.unauthorized);
      expect(f.message, 'Sesi Anda telah berakhir. Silakan login kembali.');
    });

    test('tenant codes keep the backend (Indonesian) message and code', () {
      final f = mapErrorResponse(403, {
        'success': false,
        'message': 'Anda bukan anggota tenant ini.',
        'code': 'TENANT_ACCESS_DENIED',
        'errors': [],
      });
      expect(f.kind, FailureKind.tenant);
      expect(f.code, 'TENANT_ACCESS_DENIED');
      expect(f.message, 'Anda bukan anggota tenant ini.');
    });

    test('TENANT_REQUIRED (409) is a tenant failure', () {
      final f = mapErrorResponse(409, {'message': 'Pilih perusahaan (tenant) terlebih dahulu.', 'code': 'TENANT_REQUIRED'});
      expect(f.kind, FailureKind.tenant);
    });

    test('generic 403 hides the English framework message', () {
      final f = mapErrorResponse(403, {'success': false, 'message': 'This action is unauthorized.', 'errors': []});
      expect(f.kind, FailureKind.forbidden);
      expect(f.message, 'Anda tidak memiliki akses untuk fitur ini.');
    });

    test('plan module 403 shows the backend message', () {
      final f = mapErrorResponse(403, {
        'message': 'Fitur Sales tidak tersedia di paket Anda. Upgrade paket untuk menggunakannya.',
        'code': 'PLAN_MODULE_UNAVAILABLE',
      });
      expect(f.message, startsWith('Fitur Sales tidak tersedia'));
    });

    test('404 never shows the raw model message', () {
      final f = mapErrorResponse(404, {'message': 'No query results for model [App\\Models\\Sale] 9'});
      expect(f.kind, FailureKind.notFound);
      expect(f.message, 'Data tidak ditemukan.');
    });

    test('422 business message (stock) is shown as-is with field errors', () {
      final f = mapErrorResponse(422, {
        'success': false,
        'message': 'Validasi Gagal',
        'errors': {
          'items': ['Stok Kopi tidak mencukupi (tersisa 1).'],
        },
      });
      expect(f.kind, FailureKind.validation);
      expect(f.message, 'Stok Kopi tidak mencukupi (tersisa 1).');
      expect(f.fieldError('items'), 'Stok Kopi tidak mencukupi (tersisa 1).');
    });

    test('422 English framework message becomes a generic Indonesian one', () {
      final f = mapErrorResponse(422, {
        'message': 'Validasi Gagal',
        'errors': {
          'items.0.product_id': ['The selected items.0.product_id is invalid.'],
        },
      });
      expect(f.message, 'Data tidak valid. Periksa kembali isian Anda.');
    });

    test('429 and 500', () {
      expect(mapErrorResponse(429, {'message': 'Too Many Attempts.'}).kind, FailureKind.rateLimited);
      final server = mapErrorResponse(500, {'message': 'Server Error'});
      expect(server.kind, FailureKind.server);
      expect(server.message, 'Terjadi kesalahan pada server. Silakan coba lagi.');
    });

    test('non-JSON body is handled', () {
      expect(mapErrorResponse(502, '<html>Bad Gateway</html>').kind, FailureKind.server);
    });
  });

  group('mapDioException', () {
    DioException err(DioExceptionType type) => DioException(requestOptions: RequestOptions(path: '/x'), type: type);

    test('connection timeout: request never reached the server', () {
      final f = mapDioException(err(DioExceptionType.connectionTimeout));
      expect(f.kind, FailureKind.timeout);
      expect(f.mayHaveReachedServer, isFalse);
    });

    test('receive timeout: the server may have processed the request', () {
      final f = mapDioException(err(DioExceptionType.receiveTimeout));
      expect(f.kind, FailureKind.timeout);
      expect(f.mayHaveReachedServer, isTrue);
    });

    test('connection error is a network failure', () {
      final f = mapDioException(err(DioExceptionType.connectionError));
      expect(f.kind, FailureKind.network);
      expect(f.mayHaveReachedServer, isFalse);
    });
  });
}
