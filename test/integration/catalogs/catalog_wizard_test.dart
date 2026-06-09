@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol_finders/patrol_finders.dart';

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

void main() {
  setUpAll(() => initTestLocale());

  group('Catalog wizard (T4b)', () {
    testWidgets('happy path source=manual → POST /api/v1/catalogs + navigate',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/field-types', body: kFieldTypes);
      mock.when('/api/v1/catalogs', method: 'POST', body: kCreatedCatalog);
      // Detail endpoint after navigation
      mock.when('/api/v1/catalogs/by-slug/{slug}', body: kCreatedCatalog);
      _mockSupportingRoutes(mock);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      // Navigate to /catalogs
      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/catalogs');
      await tester.pumpAndSettle();

      // Tap "+ Nuevo catálogo" to open wizard
      final newBtn = find.byKey(const Key('catalog_new_btn'));
      expect(newBtn, findsOneWidget, reason: 'New catalog button should exist');
      await tester.tap(newBtn);
      await tester.pumpAndSettle();

      // ── Step 0: fill name + slug ──────────────────────────────────────────
      expect(find.text('Nuevo catálogo'), findsOneWidget);

      final nameField = find.byKey(const Key('wizard_name'));
      expect(nameField, findsOneWidget);
      final nameInput = find.descendant(
        of: nameField,
        matching: find.byType(TextField),
      );
      await tester.enterText(nameInput, 'Productos');
      await tester.pumpAndSettle();

      // Slug auto-generates from name — verify it's populated
      final slugField = find.byKey(const Key('wizard_slug'));
      expect(slugField, findsOneWidget);
      final slugInput = find.descendant(
        of: slugField,
        matching: find.byType(TextField),
      );
      // Verify auto-generated slug
      final slugCtrl =
          tester.widget<TextField>(slugInput).controller!;
      expect(slugCtrl.text, 'productos',
          reason: 'Slug should auto-generate from name');

      // Tap next → step 1
      final nextBtn = find.byKey(const Key('wizard_next'));
      expect(nextBtn, findsOneWidget);
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // ── Step 1: source = manual (default) ─────────────────────────────────
      final manualCard =
          find.byKey(const ValueKey('wizard_source_manual'));
      expect(manualCard, findsOneWidget);
      // Manual is already selected by default — just advance
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      // ── Step 2: add 1 field, set PK + display ─────────────────────────────
      expect(find.text('Campos del catálogo'), findsOneWidget);

      // Tap "Agregar campo"
      final addFieldBtn = find.byKey(const Key('wizard_add_field'));
      expect(addFieldBtn, findsOneWidget);
      await tester.tap(addFieldBtn);
      await tester.pumpAndSettle();

      // The field row has two _MiniTextFields with hints 'key' and 'label'
      final keyHintField = find.widgetWithText(TextField, 'key');
      final labelHintField = find.widgetWithText(TextField, 'label');

      // Enter field key
      if (keyHintField.evaluate().isNotEmpty) {
        await tester.enterText(keyHintField.first, 'sku');
        await tester.pumpAndSettle();
      }

      // Enter field label
      if (labelHintField.evaluate().isNotEmpty) {
        await tester.enterText(labelHintField.first, 'SKU');
        await tester.pumpAndSettle();
      }

      // Select PK dropdown — "Campo clave (PK) *"
      final pkDropdown = find.text('Campo clave (PK) *');
      expect(pkDropdown, findsOneWidget);
      // Find the dropdown near the PK label
      final pkDropdownBtn = find.descendant(
        of: find.ancestor(
          of: pkDropdown,
          matching: find.byType(Column),
        ).first,
        matching: find.byType(DropdownButton<String>),
      );
      if (pkDropdownBtn.evaluate().isNotEmpty) {
        await tester.tap(pkDropdownBtn.first);
        await tester.pumpAndSettle();
        // Select 'sku' from dropdown
        final skuOption = find.text('sku').last;
        await tester.tap(skuOption);
        await tester.pumpAndSettle();
      }

      // Select display dropdown — "Campo de display *"
      final displayDropdown = find.text('Campo de display *');
      expect(displayDropdown, findsOneWidget);
      final displayDropdownBtn = find.descendant(
        of: find.ancestor(
          of: displayDropdown,
          matching: find.byType(Column),
        ).first,
        matching: find.byType(DropdownButton<String>),
      );
      if (displayDropdownBtn.evaluate().isNotEmpty) {
        await tester.tap(displayDropdownBtn.first);
        await tester.pumpAndSettle();
        final skuDisplayOption = find.text('sku').last;
        await tester.tap(skuDisplayOption);
        await tester.pumpAndSettle();
      }

      // Tap next → step 3
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      // ── Step 3: review + submit ────────────────────────────────────────────
      expect(find.text('Resumen del catálogo'), findsOneWidget);

      final submitBtn = find.byKey(const Key('wizard_submit'));
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify POST /api/v1/catalogs was sent
      final createCalls =
          mock.captured('/api/v1/catalogs', method: 'POST');
      expect(createCalls, isNotEmpty,
          reason: 'Should have sent POST /api/v1/catalogs');
      final body = createCalls.last.data as Map;
      expect(body['label'], 'Productos');
      expect(body['slug'], 'productos');
      expect(body['source_type'], 'manual');
      expect(body['fields_schema'], isNotEmpty);

      // source=manual → NO sync call expected
      final syncCalls =
          mock.captured('/api/v1/catalogs/{id}/sync', method: 'POST');
      expect(syncCalls, isEmpty,
          reason: 'Manual source should NOT trigger sync');

      // Verify navigation to /catalogs/productos
      await tester.pumpAndSettle();
      final routerState = GoRouterState.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(
        routerState.uri.toString(),
        contains('/catalogs/productos'),
        reason: 'Should navigate to /catalogs/<slug> after wizard',
      );

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('source=google_sheets shows connected state when OAuth OK',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/field-types', body: kFieldTypes);
      mock.when('/integrations/google/status', body: kGoogleConnected);
      _mockSupportingRoutes(mock);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      // Navigate to /catalogs
      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/catalogs');
      await tester.pumpAndSettle();

      // Open wizard
      await tester.tap(find.byKey(const Key('catalog_new_btn')));
      await tester.pumpAndSettle();

      // Step 0: fill name + slug so we can advance
      final nameInput = find.descendant(
        of: find.byKey(const Key('wizard_name')),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameInput, 'Test');
      await tester.pumpAndSettle();

      // Advance to step 1
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      // Tap Google Sheets source card
      final gsCard =
          find.byKey(const ValueKey('wizard_source_google_sheets'));
      expect(gsCard, findsOneWidget);
      await tester.tap(gsCard);
      await tester.pumpAndSettle();

      // Wait for OAuth check to complete
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify "Google conectado" is shown (not the warning)
      expect(find.text('Google conectado'), findsOneWidget,
          reason: 'Should show connected state when OAuth returns connected');
      expect(find.text('Tu cuenta de Google no está conectada.'),
          findsNothing,
          reason: 'Should NOT show disconnected warning');

      // patrol_finders assertion
      final $ = PatrolTester(
        tester: tester,
        config: const PatrolTesterConfig(),
      );
      expect($('Google conectado'), findsOneWidget);

      // Close dialog to avoid pending timers
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
