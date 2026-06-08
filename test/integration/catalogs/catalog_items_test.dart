@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:conectamos_platform/core/api/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/catalog_fixtures.dart';
import '../helpers/in_memory_key_value_store.dart';
import '../helpers/mock_api_interceptor.dart';
import '../helpers/test_overrides.dart';

void _initStaticApiClient(MockApiInterceptor mock) {
  final store = InMemoryKeyValueStore();
  final fakeClient = SupabaseClient(
    'http://localhost:0',
    'fake-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  ApiClient.resetForTest();
  ApiClient.init(
    supabaseClient: fakeClient,
    storage: store,
    testInterceptor: mock,
  );
}

void _mockSupportingRoutes(MockApiInterceptor mock) {
  mock.when('/operators', body: []);
  mock.when('/workers', body: []);
  mock.when('/escalations', body: []);
  mock.when('/tenants/{id}/kpis', body: <String, dynamic>{});
  mock.when('/api/v1/catalogs', body: kCatalogList);
}

/// Mocks required by all tabs that mount when the detail screen opens.
void _mockDetailTabs(MockApiInterceptor mock) {
  mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalogWithSchema);
  mock.when('/api/v1/catalogs/{id}/items', method: 'GET', body: kItemsPage);
  mock.when('/api/v1/catalogs/{id}/sync-log', body: []);
  mock.when('/api/v1/catalogs/{id}/usages', body: kCatalogUsages);
}

Future<void> _navigateToDetail(WidgetTester tester) async {
  final scaffold = find.byType(Scaffold).first;
  GoRouter.of(tester.element(scaffold)).go('/catalogs/productos');
  await tester.pumpAndSettle();
  // Wait for all tabs to load
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initTestLocale());

  group('Catalog items CRUD (T4c)', () {
    testWidgets('list: detail renders item rows from paged response',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockDetailTabs(mock);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester);

      // Switch to Items tab
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      // Both item rows should be visible
      expect(
        find.byKey(const ValueKey('item_row_item-001')),
        findsOneWidget,
        reason: 'First item row should render',
      );
      expect(
        find.byKey(const ValueKey('item_row_item-002')),
        findsOneWidget,
        reason: 'Second item row should render',
      );

      // Item data should be visible
      expect(find.text('A100'), findsOneWidget);
      expect(find.text('Widget B'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('create: add item dialog → POST with body.data',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockDetailTabs(mock);
      mock.when('/api/v1/catalogs/{id}/items',
          method: 'POST', body: kCreatedItem);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester);

      // Switch to Items tab
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      // Tap "Agregar"
      final addBtn = find.byKey(const Key('items_add_btn'));
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Agregar item'), findsOneWidget);

      // Fill fields by stable Key (namespaced by field key from schema)
      final skuInput = find.descendant(
        of: find.byKey(const ValueKey('item_field_sku')),
        matching: find.byType(TextField),
      );
      expect(skuInput, findsOneWidget);
      await tester.enterText(skuInput, 'C300');
      await tester.pumpAndSettle();

      final nombreInput = find.descendant(
        of: find.byKey(const ValueKey('item_field_nombre')),
        matching: find.byType(TextField),
      );
      expect(nombreInput, findsOneWidget);
      await tester.enterText(nombreInput, 'Widget C');
      await tester.pumpAndSettle();

      // Tap save
      final saveBtn = find.byKey(const Key('item_add_save'));
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify POST /api/v1/catalogs/{id}/items
      final createCalls =
          mock.captured('/api/v1/catalogs/{id}/items', method: 'POST');
      expect(createCalls, isNotEmpty,
          reason: 'Should have sent POST /api/v1/catalogs/{id}/items');
      final body = createCalls.last.data as Map;
      final data = body['data'] as Map;
      expect(data['sku'], 'C300');
      expect(data['nombre'], 'Widget C');

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('edit: item detail → edit dialog → PUT with body.data',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockDetailTabs(mock);
      mock.when('/api/v1/catalogs/{id}/items/{id}',
          method: 'PUT', body: kCatalogItems[0]);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester);

      // Switch to Items tab
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      // Tap first item row to open bottom sheet
      final row = find.byKey(const ValueKey('item_row_item-001'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();

      // Bottom sheet should show "Detalle del item"
      expect(find.text('Detalle del item'), findsOneWidget);

      // Tap edit icon
      final editBtn = find.byKey(const Key('item_detail_edit'));
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Edit dialog should show "Editar item"
      expect(find.text('Editar item'), findsOneWidget);

      // Edit the Nombre field by stable Key
      final nombreInput = find.descendant(
        of: find.byKey(const ValueKey('item_field_nombre')),
        matching: find.byType(TextField),
      );
      expect(nombreInput, findsOneWidget);
      await tester.enterText(nombreInput, 'Widget A Updated');
      await tester.pumpAndSettle();

      // Tap save
      final saveBtn = find.byKey(const Key('item_edit_save'));
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify PUT /api/v1/catalogs/{id}/items/{id}
      final updateCalls =
          mock.captured('/api/v1/catalogs/{id}/items/{id}', method: 'PUT');
      expect(updateCalls, isNotEmpty,
          reason: 'Should have sent PUT /api/v1/catalogs/{id}/items/{id}');
      final body = updateCalls.last.data as Map;
      final data = body['data'] as Map;
      expect(data['nombre'], 'Widget A Updated');

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('delete: item detail → confirm → DELETE',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockDetailTabs(mock);
      mock.when('/api/v1/catalogs/{id}/items/{id}',
          method: 'DELETE', body: kDeletedItemResponse);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester);

      // Switch to Items tab
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      // Tap first item row to open bottom sheet
      final row = find.byKey(const ValueKey('item_row_item-001'));
      expect(row, findsOneWidget);
      await tester.tap(row);
      await tester.pumpAndSettle();

      // Tap delete icon
      final deleteBtn = find.byKey(const Key('item_detail_delete'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Confirm dialog should be visible
      expect(find.text('Eliminar item'), findsOneWidget);

      // Tap confirm
      final confirmBtn = find.byKey(const Key('confirm_dialog_ok'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify DELETE was sent
      final deleteCalls = mock.captured(
        '/api/v1/catalogs/{id}/items/{id}',
        method: 'DELETE',
      );
      expect(deleteCalls, isNotEmpty,
          reason:
              'Should have sent DELETE /api/v1/catalogs/{id}/items/{id}');
      expect(deleteCalls.last.path, '/api/v1/catalogs/cat-001/items/item-001');

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
