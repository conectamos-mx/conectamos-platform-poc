import 'package:dio/dio.dart';

/// Structured error extracted from backend 4xx responses.
///
/// Backend convention: `{ "error_code": "SOME_CODE", "message": "...", ...metadata }`.
/// The interceptor in [ApiClient] rejects with [ApiError] so callers can
/// `switch` on [errorCode] instead of string-matching.
class ApiError implements Exception {
  const ApiError({
    required this.statusCode,
    required this.errorCode,
    required this.message,
    this.meta = const {},
  });

  final int statusCode;
  final String errorCode;
  final String message;
  final Map<String, dynamic> meta;

  /// Tries to extract a structured [ApiError] from a [DioException].
  /// Returns `null` if the response body doesn't follow the convention.
  ///
  /// Supports both layouts:
  /// - Root: `{"error_code": "...", "message": "...", ...}`
  /// - FastAPI detail-wrapped: `{"detail": {"error_code": "...", ...}}`
  static ApiError? from(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) return null;
    final data = e.response?.data;
    if (data is! Map) return null;

    // Resolve the payload: unwrap "detail" if error_code lives there
    Map payload;
    if (data['error_code'] is String) {
      payload = data;
    } else if (data['detail'] is Map && data['detail']['error_code'] is String) {
      payload = data['detail'] as Map;
    } else {
      return null;
    }

    final errorCode = payload['error_code'] as String;
    final message = (payload['message'] ?? '') as String;
    final meta = Map<String, dynamic>.from(payload)
      ..remove('error_code')
      ..remove('message');

    return ApiError(
      statusCode: status,
      errorCode: errorCode,
      message: message,
      meta: meta,
    );
  }

  @override
  String toString() => 'ApiError($statusCode $errorCode: $message)';
}
