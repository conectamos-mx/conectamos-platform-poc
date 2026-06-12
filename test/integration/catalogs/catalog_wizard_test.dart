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
  mock.when('/api/v1/catalogs', body: kCatalogList);
}

/// Navigate to wizard step 0, fill name, and advance to step 1.
Future<void> _openWizardAndAdvanceToStep1(WidgetTester tester) async {
  final scaffold = find.byType(Scaffold).first;
  GoRouter.of(tester.element(scaffold)).go('/catalogs');
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('catalog_new_btn')));
  await tester.pumpAndSettle();

  // Step 0: fill name so we can advance
  final nameInput = find.descendant(
    of: find.byKey(const Key('wizard_name')),
    matching: find.byType(TextField),
  );
  await tester.enterText(nameInput, 'Test');
  await tester.pumpAndSettle();

  // Advance to step 1
  await tester.tap(find.byKey(const Key('wizard_next')));
  await tester.pumpAndSettle();
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

    testWidgets(
        'preview with column_specs populates fields with canonical keys',
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
      mock.when('/api/v1/catalogs/tools/sheets-preview',
          body: kSheetsPreviewWithSpecs);
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      await _openWizardAndAdvanceToStep1(tester);

      // Select Google Sheets source
      final gsCard =
          find.byKey(const ValueKey('wizard_source_google_sheets'));
      await tester.tap(gsCard);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Enter a sheet URL to trigger preview (debounce = 800ms)
      final sheetUrlField = find.widgetWithText(
          TextField, 'https://docs.google.com/spreadsheets/d/…');
      expect(sheetUrlField, findsOneWidget,
          reason: 'Sheet URL field should exist');
      await tester.enterText(
          sheetUrlField, 'https://docs.google.com/spreadsheets/d/abc123/edit');
      await tester.pumpAndSettle();

      // Wait for debounce (800ms) + preview load
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // Advance to step 2: fields
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      // Verify fields were prepopulated with canonical keys from column_specs
      // Field 1: key=n_de_venta, label=N. de Venta
      final field0Key = find.byKey(const Key('field_row_0'));
      expect(field0Key, findsOneWidget,
          reason: 'First field row should exist');
      final field1Key = find.byKey(const Key('field_row_1'));
      expect(field1Key, findsOneWidget,
          reason: 'Second field row should exist');
      final field2Key = find.byKey(const Key('field_row_2'));
      expect(field2Key, findsOneWidget,
          reason: 'Third field row should exist');

      // Verify canonical keys inside their respective field rows
      final row0KeyField = find.descendant(
        of: find.byKey(const Key('field_row_0')),
        matching: find.widgetWithText(TextField, 'n_de_venta'),
      );
      expect(row0KeyField, findsOneWidget,
          reason: 'Key should be canonical from BE: n_de_venta');

      final row1KeyField = find.descendant(
        of: find.byKey(const Key('field_row_1')),
        matching: find.widgetWithText(TextField, 'numero'),
      );
      expect(row1KeyField, findsOneWidget,
          reason: 'Key should be canonical from BE: numero');

      final row2KeyField = find.descendant(
        of: find.byKey(const Key('field_row_2')),
        matching: find.widgetWithText(TextField, 'doble_espacio'),
      );
      expect(row2KeyField, findsOneWidget,
          reason: 'Key should be canonical from BE: doble_espacio');

      // Verify label is the original header inside field row 0
      final row0LabelField = find.descendant(
        of: find.byKey(const Key('field_row_0')),
        matching: find.widgetWithText(TextField, 'N. de Venta'),
      );
      expect(row0LabelField, findsOneWidget,
          reason: 'Label should be original header');

      // Verify key fields are read-only (source=google_sheets + columnsFromPreview)
      for (final rowKey in [
        const Key('field_row_0'),
        const Key('field_row_1'),
        const Key('field_row_2'),
      ]) {
        final allTextFields = find.descendant(
          of: find.byKey(rowKey),
          matching: find.byType(TextField),
        );
        // First TextField in the row is the key field
        final keyTextField = tester.widget<TextField>(allTextFields.first);
        expect(keyTextField.readOnly, isTrue,
            reason: 'Key field in $rowKey should be readOnly for google_sheets');
      }

      // Close dialog to avoid pending timers
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        'preview WITHOUT column_specs shows error and creates zero fields',
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
      mock.when('/api/v1/catalogs/tools/sheets-preview',
          body: kSheetsPreviewLegacy);
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      await _openWizardAndAdvanceToStep1(tester);

      // Select Google Sheets source
      final gsCard =
          find.byKey(const ValueKey('wizard_source_google_sheets'));
      await tester.tap(gsCard);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Enter a sheet URL to trigger preview
      final sheetUrlField = find.widgetWithText(
          TextField, 'https://docs.google.com/spreadsheets/d/…');
      await tester.enterText(
          sheetUrlField, 'https://docs.google.com/spreadsheets/d/abc123/edit');
      await tester.pumpAndSettle();

      // Wait for debounce + preview load
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // Verify SnackBar error is shown via Key
      expect(find.byKey(const Key('preview_missing_specs_error')),
          findsOneWidget,
          reason: 'SnackBar with missing column_specs error should be visible');

      // Advance to step 2 and verify zero fields were created
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      expect(find.text('Sin campos — agrega al menos uno.'), findsOneWidget,
          reason: 'Fields list should be empty when column_specs is missing');

      // Close dialog to avoid pending timers
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('source=manual keeps key field editable', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/api/v1/field-types', body: kFieldTypes);
      _mockSupportingRoutes(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      await _openWizardAndAdvanceToStep1(tester);

      // source=manual is default — advance to step 2
      await tester.tap(find.byKey(const Key('wizard_next')));
      await tester.pumpAndSettle();

      // Add a field manually
      await tester.tap(find.byKey(const Key('wizard_add_field')));
      await tester.pumpAndSettle();

      // Key field should be editable
      final keyFields = find.widgetWithText(TextField, 'key');
      expect(keyFields, findsOneWidget,
          reason: 'One key field should exist after adding a field');
      final textField = tester.widget<TextField>(keyFields.first);
      expect(textField.readOnly, isFalse,
          reason: 'Key field should be editable for manual source');

      // Close dialog to avoid pending timers
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
