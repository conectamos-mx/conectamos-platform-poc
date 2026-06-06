import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/api/api_error.dart';

/// Creates a minimal [DioException] with the given [statusCode] and [data].
DioException _makeDioException({int? statusCode, dynamic data}) {
  final opts = RequestOptions(path: '/test');
  return DioException(
    requestOptions: opts,
    response: statusCode != null
        ? Response(requestOptions: opts, statusCode: statusCode, data: data)
        : null,
  );
}

void main() {
  // ── Layout A: error_code at root ──────────────────────────────────────────

  group('ApiError.from — root layout', () {
    test('extracts error_code and message from root', () {
      final e = _makeDioException(statusCode: 422, data: {
        'error_code': 'DUPLICATE_PHONE',
        'message': 'Phone already exists',
      });
      final err = ApiError.from(e);
      expect(err, isNotNull);
      expect(err!.statusCode, 422);
      expect(err.errorCode, 'DUPLICATE_PHONE');
      expect(err.message, 'Phone already exists');
    });

    test('captures extra keys in meta', () {
      final e = _makeDioException(statusCode: 409, data: {
        'error_code': 'CONFLICT',
        'message': 'Already exists',
        'existing_id': 'abc-123',
      });
      final err = ApiError.from(e)!;
      expect(err.meta['existing_id'], 'abc-123');
      expect(err.meta.containsKey('error_code'), isFalse);
      expect(err.meta.containsKey('message'), isFalse);
    });

    test('defaults message to empty string when missing', () {
      final e = _makeDioException(statusCode: 400, data: {
        'error_code': 'BAD_REQUEST',
      });
      final err = ApiError.from(e)!;
      expect(err.message, '');
    });
  });

  // ── Layout B: error_code inside detail ────────────────────────────────────

  group('ApiError.from — FastAPI detail layout', () {
    test('unwraps detail wrapper', () {
      final e = _makeDioException(statusCode: 422, data: {
        'detail': {
          'error_code': 'VALIDATION_ERROR',
          'message': 'Invalid field',
          'field': 'phone',
        },
      });
      final err = ApiError.from(e);
      expect(err, isNotNull);
      expect(err!.errorCode, 'VALIDATION_ERROR');
      expect(err.message, 'Invalid field');
      expect(err.meta['field'], 'phone');
    });
  });

  // ── Null / unrecognised paths ─────────────────────────────────────────────

  group('ApiError.from — null paths', () {
    test('returns null when DioException has no response', () {
      final e = DioException(requestOptions: RequestOptions(path: '/test'));
      expect(ApiError.from(e), isNull);
    });

    test('returns null when response has no statusCode', () {
      // DioException with a response that has null statusCode
      final opts = RequestOptions(path: '/test');
      final e = DioException(
        requestOptions: opts,
        response: Response(requestOptions: opts, data: {'error_code': 'X'}),
        // statusCode defaults to null when not provided
      );
      // Response constructor without statusCode → null
      expect(ApiError.from(e), isNull);
    });

    test('returns null when body is not a Map', () {
      final e = _makeDioException(statusCode: 500, data: 'Internal error');
      expect(ApiError.from(e), isNull);
    });

    test('returns null when body has no error_code anywhere', () {
      final e = _makeDioException(statusCode: 400, data: {
        'message': 'Something went wrong',
      });
      expect(ApiError.from(e), isNull);
    });

    test('returns null when detail is a string (FastAPI default)', () {
      final e = _makeDioException(statusCode: 422, data: {
        'detail': 'Not Found',
      });
      expect(ApiError.from(e), isNull);
    });

    test('returns null when detail is Map but without error_code', () {
      final e = _makeDioException(statusCode: 422, data: {
        'detail': {'msg': 'field required'},
      });
      expect(ApiError.from(e), isNull);
    });
  });

  // ── toString ──────────────────────────────────────────────────────────────

  group('ApiError.toString', () {
    test('formats as expected', () {
      const err = ApiError(
        statusCode: 403,
        errorCode: 'FORBIDDEN',
        message: 'No access',
      );
      expect(err.toString(), 'ApiError(403 FORBIDDEN: No access)');
    });
  });
}
