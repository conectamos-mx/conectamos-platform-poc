import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:conectamos_platform/core/api/api_client.dart';
import 'package:conectamos_platform/core/providers/auth_provider.dart';
import 'package:conectamos_platform/core/providers/tenant_provider.dart';
import 'package:conectamos_platform/core/storage/key_value_store.dart';
import 'package:conectamos_platform/core/router/app_router.dart';
import 'package:conectamos_platform/core/theme/app_theme.dart';

import 'in_memory_key_value_store.dart';
import 'mock_api_interceptor.dart';

// Usage:
//   await initTestLocale();                       // once per test file
//   await tester.pumpWidget(buildTestAppWithMock(mock));
//   await tester.pumpAndSettle();
//   // App starts at /overview in mock mode.
//
// Requires: flutter test --platform chrome --dart-define=MOCK_MODE=true

/// Initializes locale data required by DateFormat('es_MX'/'es') in production
/// code. Mirrors main.dart:29-30. Idempotent — safe to call multiple times.
/// Call in setUpAll() of every integration test file, or use
/// [ensureTestLocale] for a fire-and-forget approach.
Future<void> initTestLocale() async {
  await initializeDateFormatting('es_MX', null);
  await initializeDateFormatting('es', null);
}

/// Builds a test app with a [MockApiInterceptor] injected into [apiClientProvider].
/// Use this for tests that call IAM or other API methods via the provider path.
Widget buildTestAppWithMock(MockApiInterceptor mock) {
  final store = InMemoryKeyValueStore();
  final fakeClient = SupabaseClient(
    'http://localhost:0',
    'fake-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final client = ApiClient(
    supabaseClient: fakeClient,
    storage: store,
    testInterceptor: mock,
  );

  return ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      supabaseClientProvider.overrideWithValue(fakeClient),
      authStateProvider.overrideWith(
        (ref) => const Stream<AuthState>.empty(),
      ),
      activeTenantIdProvider.overrideWithValue('test-tenant-id'),
      activeTenantDisplayProvider.overrideWithValue('Test Tenant'),
      allTenantsProvider.overrideWithValue([
        TenantInfo(
          id: 'test-tenant-id',
          slug: 'test',
          displayName: 'Test Tenant',
        ),
      ]),

      // Inject mock into the provider-based ApiClient
      apiClientProvider.overrideWithValue(client),
    ],
    child: const _TestApp(),
  );
}

/// Like [buildTestAppWithMock] but accepts extra provider overrides
/// (e.g. seeded StateNotifier for family providers).
Widget buildTestAppWithMockAndOverrides(
  MockApiInterceptor mock, {
  List<Override> additionalOverrides = const [],
}) {
  final store = InMemoryKeyValueStore();
  final fakeClient = SupabaseClient(
    'http://localhost:0',
    'fake-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final client = ApiClient(
    supabaseClient: fakeClient,
    storage: store,
    testInterceptor: mock,
  );

  return ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store),
      supabaseClientProvider.overrideWithValue(fakeClient),
      authStateProvider.overrideWith(
        (ref) => const Stream<AuthState>.empty(),
      ),
      activeTenantIdProvider.overrideWithValue('test-tenant-id'),
      activeTenantDisplayProvider.overrideWithValue('Test Tenant'),
      allTenantsProvider.overrideWithValue([
        TenantInfo(
          id: 'test-tenant-id',
          slug: 'test',
          displayName: 'Test Tenant',
        ),
      ]),
      apiClientProvider.overrideWithValue(client),
      ...additionalOverrides,
    ],
    child: const _TestApp(),
  );
}

class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'ConectamOS Test',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
