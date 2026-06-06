import 'package:dio/dio.dart';

// Usage:
//   final mock = MockApiInterceptor();
//   mock.when('/tenants/{id}/kpis', body: {'operators_active': 5});
//   mock.whenError('/tenants/{id}/kpis');
//   ApiClient.init(supabaseClient: ..., storage: ..., interceptor: mock);
//
// Path patterns: literal segments match exactly; {param} matches any single segment.
// Default (no match): throws DioException with "No mock registered for <path>".

class MockApiInterceptor extends Interceptor {
  final List<_MockRoute> _routes = [];

  /// Register a successful response for [pathPattern].
  /// [body] is the response data; [statusCode] defaults to 200.
  void when(String pathPattern, {Object? body, int statusCode = 200}) {
    _routes.add(_MockRoute(
      pattern: pathPattern,
      response: Response(
        requestOptions: RequestOptions(path: pathPattern),
        data: body,
        statusCode: statusCode,
      ),
    ));
  }

  /// Register an error response for [pathPattern].
  /// Throws a [DioException] with [type] (defaults to connectionError).
  void whenError(
    String pathPattern, {
    DioExceptionType type = DioExceptionType.connectionError,
    String message = 'MockApiInterceptor: forced error',
  }) {
    _routes.add(_MockRoute(
      pattern: pathPattern,
      error: DioException(
        requestOptions: RequestOptions(path: pathPattern),
        type: type,
        message: message,
      ),
    ));
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    for (final route in _routes) {
      if (_matches(route.pattern, path)) {
        if (route.error != null) {
          return handler.reject(
            DioException(
              requestOptions: options,
              type: route.error!.type,
              message: route.error!.message,
            ),
          );
        }
        return handler.resolve(
          Response(
            requestOptions: options,
            data: route.response!.data,
            statusCode: route.response!.statusCode,
          ),
        );
      }
    }
    // No match → fail loud so unmocked requests are noticed.
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      message: 'MockApiInterceptor: no mock registered for $path',
    ));
  }

  /// Match [pattern] against [path]. `{param}` matches any single segment.
  static bool _matches(String pattern, String path) {
    final ps = pattern.split('/');
    final ts = path.split('/');
    if (ps.length != ts.length) return false;
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].startsWith('{') && ps[i].endsWith('}')) continue;
      if (ps[i] != ts[i]) return false;
    }
    return true;
  }
}

class _MockRoute {
  _MockRoute({required this.pattern, this.response, this.error});
  final String pattern;
  final Response? response;
  final DioException? error;
}
