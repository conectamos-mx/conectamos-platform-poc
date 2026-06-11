@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/catalog_fixtures.dart';
import '../helpers/mock_api_interceptor.dart';
import '../helpers/test_overrides.dart';

void _mockSupportingRoutes(MockApiInterceptor mock) {
  mock.when('/operators', body: []);
  mock.when('/workers', body: []);
  mock.when('/escalations', body: []);
  mock.when('/tenants/{id}/kpis', body: <String, dynamic>{});
  mock.when('/api/v1/catalogs', body: kCatalogList);
}

/// Mocks for all tabs that mount when a manual catalog detail opens.
void _mockManualDetailTabs(MockApiInterceptor mock) {
  mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalogWithSchema);
  mock.when('/api/v1/catalogs/{id}/items', method: 'GET', body: kItemsPage);
  mock.when('/api/v1/catalogs/{id}/sync-log', body: []);
  mock.when('/api/v1/catalogs/{id}/usages', body: kCatalogUsages);
}

/// Mocks for Google Sheets catalog detail (adds OAuth status).
void _mockGoogleSheetsDetailTabs(MockApiInterceptor mock) {
  mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalogGoogleSheets);
  mock.when('/api/v1/catalogs/{id}/items', method: 'GET',
      body: <String, dynamic>{'items': [], 'total': 0, 'page': 1, 'pages': 1});
  mock.when('/api/v1/catalogs/{id}/sync-log', body: kCatalogSyncLog);
  mock.when('/api/v1/catalogs/{id}/usages', body: []);
  mock.when('/integrations/google/status', body: kGoogleConnected);
}

Future<void> _navigateToDetail(WidgetTester tester, String slug) async {
  final scaffold = find.byType(Scaffold).first;
  GoRouter.of(tester.element(scaffold)).go('/catalogs/$slug');
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initTestLocale());

  group('Catalog detail tabs (T4d)', () {
    testWidgets('source edit: change sheet URL → PUT /api/v1/catalogs/{id}',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockGoogleSheetsDetailTabs(mock);
      mock.when('/api/v1/catalogs/{id}', method: 'PUT',
          body: kCatalogGoogleSheets);
      // Mock sheets-preview triggered by URL edit debounce
      mock.when('/api/v1/catalogs/tools/sheets-preview', body: <String, dynamic>{
        'sheets': ['Sheet1', 'Sheet2'],
        'selected_sheet': 'Sheet1',
        'columns': ['id', 'nombre'],
      });

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester, 'sucursales');

      // Switch to Fuente tab
      await tester.tap(find.text('Fuente'));
      await tester.pumpAndSettle();

      // Edit sheet URL
      final sheetUrlField = find.byKey(const Key('source_sheet_url'));
      expect(sheetUrlField, findsOneWidget);
      await tester.enterText(sheetUrlField,
          'https://docs.google.com/spreadsheets/d/xyz999/edit');
      await tester.pumpAndSettle();

      // Wait for debounce (800ms) + preview load
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // Tap Guardar
      final saveBtn = find.byKey(const Key('detail_save_btn'));
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify PUT
      final putCalls =
          mock.captured('/api/v1/catalogs/{id}', method: 'PUT');
      expect(putCalls, isNotEmpty,
          reason: 'Should have sent PUT /api/v1/catalogs/{id}');
      final body = putCalls.last.data as Map;
      expect(body['sheet_url'],
          'https://docs.google.com/spreadsheets/d/xyz999/edit');

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('uso: renders usage rows + empty state', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockManualDetailTabs(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester, 'productos');

      // Switch to Uso tab
      await tester.tap(find.text('Uso'));
      await tester.pumpAndSettle();

      // Usage row should render
      expect(
        find.byKey(const ValueKey('usage_ventas')),
        findsOneWidget,
        reason: 'Usage row for flow "ventas" should render',
      );
      expect(find.text('Flujo de ventas'), findsOneWidget);
      expect(find.text('Campo: producto_id'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('uso: empty state when no usages', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      // Override usages to empty
      mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalogWithSchema);
      mock.when('/api/v1/catalogs/{id}/items', method: 'GET', body: kItemsPage);
      mock.when('/api/v1/catalogs/{id}/sync-log', body: []);
      mock.when('/api/v1/catalogs/{id}/usages', body: []);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester, 'productos');

      // Switch to Uso tab
      await tester.tap(find.text('Uso'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('uso_empty_state')),
        findsOneWidget,
        reason: 'Empty state should render when no usages',
      );

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('delete: confirm → DELETE + navigate to /catalogs',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      _mockManualDetailTabs(mock);
      mock.when('/api/v1/catalogs/{id}', method: 'DELETE', body: null);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester, 'productos');

      // Tap delete button
      final deleteBtn = find.byKey(const Key('detail_delete_btn'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Confirm dialog should appear
      expect(find.text('Eliminar catálogo'), findsOneWidget);

      // Tap confirm
      final confirmBtn = find.byKey(const Key('delete_catalog_confirm'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify DELETE was sent
      final deleteCalls =
          mock.captured('/api/v1/catalogs/{id}', method: 'DELETE');
      expect(deleteCalls, isNotEmpty,
          reason: 'Should have sent DELETE /api/v1/catalogs/{id}');
      expect(deleteCalls.last.path, '/api/v1/catalogs/cat-001');

      // Verify navigation back to /catalogs
      final routerState = GoRouterState.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(routerState.uri.toString(), contains('/catalogs'));

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'sync trigger: POST sync + log renders after poll cycle',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mutable log list: starts running, becomes success after first poll.
      final syncLogs = <Map<String, dynamic>>[...kSyncLogRunning];

      final mock = MockApiInterceptor();
      _mockSupportingRoutes(mock);
      // Inline mocks (can't use _mockGoogleSheetsDetailTabs because
      // sync-log must use the mutable list and MockApiInterceptor
      // resolves first-registered-match).
      mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalogGoogleSheets);
      mock.when('/api/v1/catalogs/{id}/items', method: 'GET',
          body: <String, dynamic>{'items': [], 'total': 0, 'page': 1, 'pages': 1});
      mock.when('/api/v1/catalogs/{id}/sync-log', body: syncLogs);
      mock.when('/api/v1/catalogs/{id}/usages', body: []);
      mock.when('/integrations/google/status', body: kGoogleConnected);
      mock.when('/api/v1/catalogs/{id}/sync',
          method: 'POST', body: <String, dynamic>{'status': 'running'});

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();
      await _navigateToDetail(tester, 'sucursales');

      // Tap "Sincronizar ahora"
      final syncBtn = find.byKey(const Key('detail_sync_btn'));
      expect(syncBtn, findsOneWidget);
      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      // Verify POST /api/v1/catalogs/{id}/sync
      final syncCalls =
          mock.captured('/api/v1/catalogs/{id}/sync', method: 'POST');
      expect(syncCalls, isNotEmpty,
          reason: 'Should have sent POST /api/v1/catalogs/{id}/sync');

      // _syncVersion++ remounts _SyncTab with polling=true.
      // Switch to Sincronización tab. The new _SyncTab loads logs via
      // addPostFrameCallback, so we need extra pumps.
      await tester.tap(find.text('Sincronización'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // Should show running state log
      expect(
        find.byKey(const ValueKey('sync_log_log-run-001')),
        findsOneWidget,
        reason: 'Sync log row should render',
      );

      // Now mutate the mock response to success for next poll
      syncLogs
        ..clear()
        ..addAll(kSyncLogSuccess);

      // Advance one poll interval (2 seconds)
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));

      // After poll, the log should show "Exitoso"
      expect(find.text('Exitoso'), findsOneWidget,
          reason: 'Log should show success status after poll');

      // Drain remaining timers
      await tester.pump(const Duration(seconds: 65));
    });
  });
}
