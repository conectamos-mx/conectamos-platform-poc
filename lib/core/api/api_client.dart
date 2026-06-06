import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../storage/key_value_store.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

class ApiClient {
  ApiClient({
    required SupabaseClient supabaseClient,
    required KeyValueStore storage,
    Interceptor? testInterceptor,
  }) : dio = _createDio(
         supabaseClient: supabaseClient,
         storage: storage,
         testInterceptor: testInterceptor,
       );

  final Dio dio;

  static const String baseUrl = _apiBaseUrl;

  // ── Legacy static accessor (used by ~30 API classes) ───────────────────────
  // Initialized once via init() in main.dart before runApp.
  // Immutable after first init — use resetForTest() in tests only.
  static ApiClient? _default;
  static bool _initialized = false;

  static Dio get instance {
    assert(_initialized, 'ApiClient.init() must be called before accessing instance');
    return _default!.dio;
  }

  static void init({
    required SupabaseClient supabaseClient,
    required KeyValueStore storage,
    Interceptor? testInterceptor,
  }) {
    if (_initialized) {
      throw StateError(
        'ApiClient.init() already called. '
        'In tests, call ApiClient.resetForTest() before re-initializing.',
      );
    }
    _default = ApiClient(
      supabaseClient: supabaseClient,
      storage: storage,
      testInterceptor: testInterceptor,
    );
    _initialized = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _default = null;
    _initialized = false;
  }

  // ── Shared Dio factory ─────────────────────────────────────────────────────

  static Dio _createDio({
    required SupabaseClient supabaseClient,
    required KeyValueStore storage,
    Interceptor? testInterceptor,
  }) {
    assert(
      baseUrl.isNotEmpty,
      'API_BASE_URL no está definida. Usa run_dev.sh para correr en local.',
    );
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token =
            supabaseClient.auth.currentSession?.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        final tenantId = storage.getString('conectamos_active_tenant_id');
        if (tenantId != null && tenantId.isNotEmpty) {
          options.headers['X-Tenant-ID'] = tenantId;
        }
        handler.next(options);
      },
    ));
    if (testInterceptor != null) {
      dio.interceptors.add(testInterceptor);
    }
    return dio;
  }
}

/// Provider-based ApiClient — uses same Dio factory with injected deps.
/// Future sprints will migrate API classes from ApiClient.instance to this.
final apiClientProvider = Provider<ApiClient>((ref) {
  final supabaseClient = ref.watch(supabaseClientProvider);
  final storage = ref.watch(keyValueStoreProvider);
  return ApiClient(supabaseClient: supabaseClient, storage: storage);
});
