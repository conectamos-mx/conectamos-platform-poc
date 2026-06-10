@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'helpers/test_overrides.dart';

void main() {
  setUpAll(() => initTestLocale());

  testWidgets(
    'login → submit → navigates to overview (mock mode)',
    (tester) async {
      // Use a large surface to avoid overflow errors in the test viewport.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // App starts at /overview in mock mode. Navigate to /login.
      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/login');
      await tester.pumpAndSettle();

      // -- Login screen is visible --
      expect(find.text('Iniciar sesión'), findsWidgets);

      // -- Fill email --
      final emailField = find.byKey(const Key('login_email'));
      expect(emailField, findsOneWidget);
      final emailInput = find.descendant(
        of: emailField,
        matching: find.byType(TextField),
      );
      await tester.enterText(emailInput, 'test@conectamos.mx');

      // -- Fill password --
      final passField = find.byKey(const Key('login_password'));
      expect(passField, findsOneWidget);
      final passInput = find.descendant(
        of: passField,
        matching: find.byType(TextField),
      );
      await tester.enterText(passInput, 'password123');

      // -- Tap submit --
      final submitBtn = find.byKey(const Key('login_submit'));
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);

      // In MOCK_MODE the login delays 800ms then navigates to '/'.
      // Router redirects '/' → '/overview'.
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      // -- Assert: arrived at overview --
      // OverviewScreen renders ScreenHeader(title: 'Vista general')
      // because activeTenantIdProvider is overridden with a non-empty value.
      expect(find.text('Vista general'), findsWidgets);

      // -- patrol_finders assertion to validate wiring --
      // PatrolFinder $('Vista general') matches same text finders.
      final $ = PatrolTester(
        tester: tester,
        config: const PatrolTesterConfig(),
      );
      expect($('Vista general'), findsWidgets);

      // Drain any pending timers from production widgets (animations, debounce).
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
