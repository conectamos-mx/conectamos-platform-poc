@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'helpers/mock_api_interceptor.dart';
import 'helpers/test_overrides.dart';

/// Shared routes for the sections that are NOT under test.
/// Mock them successfully so their errors don't pollute assertions.
void _mockSupportingRoutes(MockApiInterceptor mock) {
  mock.when('/operators', body: []);
  mock.when('/workers', body: []);
  mock.when('/escalations', body: []);
  mock.when('/iam/users', body: []);
  mock.when('/iam/roles', body: []);
}

void main() {
  setUpAll(() => initTestLocale());

  group('Overview KPI error states', () {
    testWidgets(
      'getKpis error → error banner visible in HeroBand',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mock = MockApiInterceptor();
        // KPIs FAIL
        mock.whenError('/tenants/{id}/kpis');
        // Other sections succeed — isolate KPI error
        _mockSupportingRoutes(mock);

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // The HeroBand should show an error indicator — not silent dashes.
        // With supporting routes mocked successfully, any error_outline icon
        // or 'Reintentar' text MUST come from KPI error handling.
        expect(find.byIcon(Icons.error_outline), findsWidgets,
            reason: 'KPI error should show error_outline icon');
        expect(find.text('Reintentar'), findsWidgets,
            reason: 'KPI error should show retry button');

        // patrol_finders wiring
        final $ = PatrolTester(
          tester: tester,
          config: const PatrolTesterConfig(),
        );
        expect($('Reintentar'), findsWidgets);

        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'getKpis returns empty → no error banner, shows dashes',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mock = MockApiInterceptor();
        // KPIs succeed with empty body
        mock.when('/tenants/{id}/kpis', body: <String, dynamic>{});
        _mockSupportingRoutes(mock);

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        // Vista general visible
        expect(find.text('Vista general'), findsWidgets);

        // No error banner anywhere — all routes succeeded
        expect(find.byIcon(Icons.error_outline), findsNothing,
            reason: 'Empty KPIs should NOT show error indicator');
        expect(find.text('Reintentar'), findsNothing,
            reason: 'Empty KPIs should NOT show retry button');

        // Dashes visible for null KPI values
        expect(find.text('—% de tu equipo está operando.'), findsOneWidget,
            reason: 'Empty KPIs should show dash placeholders');

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}
