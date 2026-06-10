@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../helpers/catalog_fixtures.dart';
import '../helpers/mock_api_interceptor.dart';
import '../helpers/test_overrides.dart';

void _mockSupportingRoutes(MockApiInterceptor mock) {
  mock.when('/operators', body: []);
  mock.when('/workers', body: []);
  mock.when('/escalations', body: []);
  mock.when('/tenants/{id}/kpis', body: <String, dynamic>{});
}

void main() {
  setUpAll(() => initTestLocale());

  group('Catalogs list (T4a)', () {
    testWidgets('renders rows from GET /api/v1/catalogs', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/catalogs', body: kCatalogList);
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      // Navigate to /catalogs
      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/catalogs');
      await tester.pumpAndSettle();

      // Both catalog rows should be visible
      expect(
        find.byKey(const ValueKey('catalog_row_cat-001')),
        findsOneWidget,
        reason: 'First catalog row should render',
      );
      expect(
        find.byKey(const ValueKey('catalog_row_cat-002')),
        findsOneWidget,
        reason: 'Second catalog row should render',
      );

      // Labels should be visible
      expect(find.text('Productos'), findsOneWidget);
      expect(find.text('Sucursales'), findsOneWidget);

      // patrol_finders assertion
      final $ = PatrolTester(
        tester: tester,
        config: const PatrolTesterConfig(),
      );
      expect($('Productos'), findsOneWidget);
      expect($('Sucursales'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('tap row navigates to /catalogs/<slug>', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/catalogs', body: kCatalogList);
      // Mock the detail endpoint so navigation doesn't error
      mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCatalog1);
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/catalogs');
      await tester.pumpAndSettle();

      // Tap on the first catalog row's name (GestureDetector wraps label)
      final row1 = find.byKey(const ValueKey('catalog_row_cat-001'));
      expect(row1, findsOneWidget);
      final rowLabel = find.descendant(
        of: row1,
        matching: find.text('Productos'),
      );
      expect(rowLabel, findsOneWidget);
      await tester.tap(rowLabel);
      await tester.pumpAndSettle();

      // Verify navigation — router location should be /catalogs/productos
      final routerState = GoRouterState.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(
        routerState.uri.toString(),
        contains('/catalogs/productos'),
        reason: 'Should navigate to /catalogs/<slug>',
      );

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('sync button sends POST /api/v1/catalogs/{id}/sync',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/catalogs', body: kCatalogList);
      mock.when('/api/v1/catalogs/{id}/sync',
          method: 'POST', body: <String, dynamic>{'status': 'running'});
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/catalogs');
      await tester.pumpAndSettle();

      // Tap sync button on first catalog row
      final syncBtn = find.byKey(const ValueKey('catalog_sync_cat-001'));
      expect(syncBtn, findsOneWidget, reason: 'Sync button should be visible');
      await tester.tap(syncBtn);
      await tester.pumpAndSettle();

      // Verify POST was sent
      final syncCalls = mock.captured(
        '/api/v1/catalogs/{id}/sync',
        method: 'POST',
      );
      expect(syncCalls, isNotEmpty,
          reason: 'Should have sent POST /api/v1/catalogs/{id}/sync');
      expect(syncCalls.last.path, '/api/v1/catalogs/cat-001/sync');

      // Verify success snackbar
      expect(find.text('Sincronización iniciada'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
