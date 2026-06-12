// Smoke E2E — real backend, real auth, zero mocks (PLA-250 / T6).
//
// Prerequisites:
//   1. chromedriver running:
//        chromedriver --port=4444
//   2. A test user with access to at least one tenant + catalogs.view
//      permission in Supabase dev.
//
// Run:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/smoke/smoke_dev_test.dart \
//     -d web-server \
//     --dart-define=API_BASE_URL=https://platform-api-dev.conectamos.ai \
//     --dart-define=SUPABASE_URL=<supabase-dev-url> \
//     --dart-define=SUPABASE_ANON_KEY=<supabase-dev-anon-key> \
//     --dart-define=SMOKE_EMAIL=<user> \
//     --dart-define=SMOKE_PASSWORD=<pass>
//
// Scope: 100 % READ-ONLY. Zero POST/PUT/DELETE.
//   a. Login real (signInWithPassword against Supabase dev).
//   b. Overview renders inside AppShell with no error state.
//   c. Navigate to /catalogs — list loads without error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:conectamos_platform/features/catalogs/catalogs_screen.dart';
import 'package:conectamos_platform/shared/widgets/app_shell.dart';

import 'smoke_app.dart';

const _email = String.fromEnvironment('SMOKE_EMAIL');
const _password = String.fromEnvironment('SMOKE_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Fail-fast if credentials are missing ──────────────────────────────────
  if (_email.isEmpty || _password.isEmpty) {
    test('credentials check', () {
      fail(
        'SMOKE_EMAIL and SMOKE_PASSWORD must be provided via --dart-define. '
        'Example: --dart-define=SMOKE_EMAIL=user@test.com '
        '--dart-define=SMOKE_PASSWORD=secret',
      );
    });
    return;
  }

  // ── Bootstrap (once) ──────────────────────────────────────────────────────
  late Widget app;

  setUpAll(() async {
    app = await buildSmokeTestApp();
  });

  // ── Smoke test ────────────────────────────────────────────────────────────
  testWidgets('smoke: login → overview → catalogs (read-only)',
      (tester) async {
    // Large viewport to match production layout and avoid overflow.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(app);

    // ── (a) Login ─────────────────────────────────────────────────────────
    // Router guard redirects unauthenticated user to /login.
    await _waitUntilFound(
      tester,
      find.byKey(const Key('login_email')),
      reason: 'Login screen should render after router guard redirect',
    );

    // Fill email
    final emailInput = find.descendant(
      of: find.byKey(const Key('login_email')),
      matching: find.byType(TextField),
    );
    await tester.enterText(emailInput, _email);

    // Fill password
    final passInput = find.descendant(
      of: find.byKey(const Key('login_password')),
      matching: find.byType(TextField),
    );
    await tester.enterText(passInput, _password);
    await tester.pump();

    // Submit
    await tester.tap(find.byKey(const Key('login_submit')));

    // ── (b) Overview ──────────────────────────────────────────────────────
    // Wait for signInWithPassword + router redirect + shell render.
    await _waitUntilFound(
      tester,
      find.byType(AppShell),
      timeout: const Duration(seconds: 30),
      reason: 'AppShell should render after successful login',
    );

    // Let all overview sections finish loading against the real backend.
    await _pumpFor(tester, const Duration(seconds: 8));

    // Assert: no error indicators in the overview or topbar.
    expect(find.byIcon(Icons.error_outline), findsNothing,
        reason: 'Overview should not show error indicators');
    expect(find.text('Reintentar'), findsNothing,
        reason: 'Overview should not show retry buttons');

    // ── (c) Catalogs ──────────────────────────────────────────────────────
    GoRouter.of(tester.element(find.byType(AppShell))).go('/catalogs');

    // Wait for CatalogsScreen to appear and finish loading.
    await _waitUntilFound(
      tester,
      find.byType(CatalogsScreen),
      reason: 'CatalogsScreen should render after navigation',
    );

    // Let the catalog list API call complete.
    await _pumpFor(tester, const Duration(seconds: 8));

    // Assert: no error state in catalogs screen.
    expect(find.text('Reintentar'), findsNothing,
        reason: 'Catalogs screen should not show error state');

    // Drain pending timers (animations, debounces).
    await tester.pump(const Duration(seconds: 5));
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Pumps frames until [finder] finds at least one widget, or fails on timeout.
Future<void> _waitUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 500),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(interval);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(reason ?? 'Timed out waiting for $finder to appear');
}

/// Pumps frames for the given [duration] without asserting anything.
/// Used to let real network calls settle before making assertions.
Future<void> _pumpFor(
  WidgetTester tester,
  Duration duration, {
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(interval);
  }
}
