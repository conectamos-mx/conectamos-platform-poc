import 'package:dio/dio.dart';

// Usage:
//   final mock = MockApiInterceptor();
//   mock.when('/tenants/{id}/kpis', body: {'operators_active': 5});
//   mock.when('/iam/users/{id}', method: 'DELETE', body: null);
//   mock.whenError('/tenants/{id}/kpis');
//   buildTestAppWithMock(mock);  // injects mock via apiClientProvider
//
// Path patterns: literal segments match exactly; {param} matches any single segment.
// Method matching (optional, PLA-103):
//   - method omitted → matches ANY HTTP verb (retrocompat with PLA-55 callers).
//   - method provided → matches only that verb (case-insensitive).
//   - When multiple routes match the same path, a route WITH method wins over
//     one WITHOUT method (specificity). First match within same specificity wins.
// Default (no match): throws DioException with "No mock registered for <path>".

class MockApiInterceptor extends Interceptor {
  final List<_MockRoute> _routes = [];

  /// All intercepted requests, in order. Use for assertions on body/method.
  final List<CapturedRequest> requests = [];

  /// Register a successful response for [pathPattern].
  /// [body] is the response data; [statusCode] defaults to 200.
  /// [method] (optional): restrict to a specific HTTP verb (case-insensitive).
  void when(
    String pathPattern, {
    String? method,
    Object? body,
    int statusCode = 200,
  }) {
    _routes.add(_MockRoute(
      pattern: pathPattern,
      method: method?.toUpperCase(),
      response: Response(
        requestOptions: RequestOptions(path: pathPattern),
        data: body,
        statusCode: statusCode,
      ),
    ));
  }

  /// Register an error response for [pathPattern].
  /// Throws a [DioException] with [type] (defaults to connectionError).
  /// [method] (optional): restrict to a specific HTTP verb (case-insensitive).
  void whenError(
    String pathPattern, {
    String? method,
    DioExceptionType type = DioExceptionType.connectionError,
    String message = 'MockApiInterceptor: forced error',
  }) {
    _routes.add(_MockRoute(
      pattern: pathPattern,
      method: method?.toUpperCase(),
      error: DioException(
        requestOptions: RequestOptions(path: pathPattern),
        type: type,
        message: message,
      ),
    ));
  }

  /// Return captured requests matching [pathPattern].
  /// [method] (optional): filter by HTTP verb (case-insensitive).
  List<CapturedRequest> captured(String pathPattern, {String? method}) {
    final upperMethod = method?.toUpperCase();
    return requests.where((r) {
      if (!_matchesPath(pathPattern, r.path)) return false;
      if (upperMethod != null && r.method.toUpperCase() != upperMethod) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final verb = options.method.toUpperCase();
    requests.add(CapturedRequest(
      method: options.method,
      path: path,
      data: options.data,
    ));

    // Two-pass resolution: prefer routes with explicit method over wildcard.
    _MockRoute? wildcard;
    for (final route in _routes) {
      if (!_matchesPath(route.pattern, path)) continue;
      if (route.method != null) {
        if (route.method == verb) return _resolve(route, options, handler);
      } else {
        wildcard ??= route;
      }
    }
    if (wildcard != null) return _resolve(wildcard, options, handler);

    // No match → fail loud so unmocked requests are noticed.
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      message: 'MockApiInterceptor: no mock registered for $verb $path',
    ));
  }

  static void _resolve(
    _MockRoute route,
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (route.error != null) {
      return handler.reject(
        DioException(
          requestOptions: options,
          type: route.error!.type,
          message: route.error!.message,
        ),
      );
    }
    handler.resolve(
      Response(
        requestOptions: options,
        data: route.response!.data,
        statusCode: route.response!.statusCode,
      ),
    );
  }

  /// Match [pattern] against [path]. `{param}` matches any single segment.
  static bool _matchesPath(String pattern, String path) {
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
  _MockRoute({
    required this.pattern,
    this.method,
    this.response,
    this.error,
  });
  final String pattern;
  final String? method;
  final Response? response;
  final DioException? error;
}

class CapturedRequest {
  const CapturedRequest({
    required this.method,
    required this.path,
    this.data,
  });
  final String method;
  final String path;
  final dynamic data;
}
