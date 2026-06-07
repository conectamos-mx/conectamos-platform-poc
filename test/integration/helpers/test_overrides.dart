import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
//   await tester.pumpWidget(buildTestApp());
//   await tester.pumpAndSettle();
//   // App starts at /overview in mock mode.
//
// Requires: flutter test --platform chrome \
//   --dart-define=MOCK_MODE=true --dart-define=API_BASE_URL=http://localhost:0

/// Builds the ConectamosApp wrapped in a ProviderScope with all providers
/// overridden so no Supabase, dart:html, or network calls occur.
Widget buildTestApp() {
  final store = InMemoryKeyValueStore();
  final fakeClient = SupabaseClient(
    'http://localhost:0',
    'fake-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  return ProviderScope(
    overrides: [
      // Storage — in-memory, no dart:html
      keyValueStoreProvider.overrideWithValue(store),

      // Supabase — fake client, no Supabase.initialize() needed
      supabaseClientProvider.overrideWithValue(fakeClient),

      // Auth — fake stream that never emits; currentUser stays null (mock mode)
      authStateProvider.overrideWith(
        (ref) => const Stream<AuthState>.empty(),
      ),

      // Tenant — pre-loaded so screens don't hit TenantsApi
      activeTenantIdProvider.overrideWithValue('test-tenant-id'),
      activeTenantDisplayProvider.overrideWithValue('Test Tenant'),
      allTenantsProvider.overrideWithValue([
        TenantInfo(
          id: 'test-tenant-id',
          slug: 'test',
          displayName: 'Test Tenant',
        ),
      ]),
    ],
    child: const _TestApp(),
  );
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
