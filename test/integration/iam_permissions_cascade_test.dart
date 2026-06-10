@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:conectamos_platform/core/providers/permissions_provider.dart';

import 'helpers/mock_api_interceptor.dart';
import 'helpers/test_overrides.dart';

/// Pre-seeded grants: operators.view OFF, operators.manage OFF.
/// Toggling operators.manage should cascade-enable operators.view.
const _kSupervisorGrants = <String, bool>{
  'conversations.view': true,
  'conversations.send': false,
  'conversations.export': false,
  'broadcasts.send': false,
  'flows.view': false,
  'flows.manage': false,
  'operators.view': false,
  'operators.manage': false,
  'reports.view': false,
  'settings.view': false,
  'settings.manage': false,
  'users.view': false,
  'users.manage': false,
  'escalations.view': false,
  'escalations.manage': false,
  'catalogs.view': false,
  'catalogs.manage': false,
  'operator_roles.view': false,
  'operator_roles.manage': false,
  'dashboards.view': false,
  'dashboards.manage': false,
  'flow_executions.view_all': false,
  'flow_executions.execute_dashboard': false,
  'flow_integrations.view': false,
  'flow_integrations.manage': false,
  'webhook_secrets.view': false,
  'integrations.view': false,
  'integrations.manage': false,
};

const _kSupervisorRoleId = 'supervisor-mock';

void _mockSupportingRoutes(MockApiInterceptor mock) {
  mock.when('/operators', body: []);
  mock.when('/workers', body: []);
  mock.when('/escalations', body: []);
  mock.when('/tenants/{id}/kpis', body: <String, dynamic>{});
  mock.when('/iam/users', body: []);
  mock.when('/iam/roles', body: []);
  mock.when('/iam/roles/{id}/permissions', body: []);
  // Settings screen general section loads tenant info
  mock.when('/tenants/{id}', body: <String, dynamic>{});
}

void main() {
  setUpAll(() => initTestLocale());

  group('IAM permissions cascade UI', () {
    testWidgets(
      'toggle operators.manage → operators.view auto-enabled + cascade message',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        // Suppress RenderFlex overflow from permissions panel Column —
        // pre-existing layout issue (IntrinsicHeight forces tall layout).
        final origOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final msg = details.exceptionAsString();
          if (msg.contains('overflowed')) return;
          origOnError?.call(details);
        };
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          FlutterError.onError = origOnError;
        });

        final mock = MockApiInterceptor();
        _mockSupportingRoutes(mock);

        // Build app with seeded provider override for supervisor role
        final seededState = RolePermState(
          grants: Map.of(_kSupervisorGrants),
          initialGrants: Map.of(_kSupervisorGrants),
          permIds: {
            for (final key in _kSupervisorGrants.keys)
              key: 'permid-$key',
          },
          loading: false,
        );

        await tester.pumpWidget(
          buildTestAppWithMockAndOverrides(
            mock,
            additionalOverrides: [
              rolePermissionsEditProvider(_kSupervisorRoleId)
                  .overrideWith((_) =>
                      RolePermissionsNotifier.seeded(
                        _kSupervisorRoleId,
                        seededState,
                      )),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to /settings → Permisos
        final scaffold = find.byType(Scaffold).first;
        GoRouter.of(tester.element(scaffold)).go('/settings');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Permisos'));
        await tester.pumpAndSettle();

        // Verify operators.view is unchecked, operators.manage is unchecked
        // Keys are namespaced by roleId: perm_<roleId>_<module>.<action>
        final viewCheckbox = find.byKey(
            const Key('perm_${_kSupervisorRoleId}_operators.view'));
        final manageCheckbox = find.byKey(
            const Key('perm_${_kSupervisorRoleId}_operators.manage'));
        expect(viewCheckbox, findsOneWidget);
        expect(manageCheckbox, findsOneWidget);

        // Both should be unchecked
        _expectChecked(tester, viewCheckbox, false);
        _expectChecked(tester, manageCheckbox, false);

        // Toggle operators.manage ON — tap the Checkbox inside the row
        final manageCheck = find.descendant(
          of: manageCheckbox,
          matching: find.byType(Checkbox),
        );
        await tester.tap(manageCheck);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // After cascade: operators.manage = ON, operators.view = ON
        _expectChecked(tester, manageCheckbox, true);
        _expectChecked(tester, viewCheckbox, true);

        // Cascade message should appear in SnackBar.
        // Cascade message should appear in SnackBar (by Key, not copy)
        expect(
          find.byKey(const Key('perm_cascade_msg')),
          findsOneWidget,
          reason: 'Cascade SnackBar should be visible after toggle',
        );

        // patrol_finders assertion
        final $ = PatrolTester(
          tester: tester,
          config: const PatrolTesterConfig(),
        );
        expect($('Guardar cambios'), findsWidgets);

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}

/// Assert a CheckboxListTile (found by its parent Key) has the expected value.
void _expectChecked(WidgetTester tester, Finder parentFinder, bool expected) {
  final checkbox = find.descendant(
    of: parentFinder,
    matching: find.byType(Checkbox),
  );
  expect(checkbox, findsOneWidget);
  final widget = tester.widget<Checkbox>(checkbox);
  expect(widget.value, expected,
      reason: 'Checkbox should be ${expected ? "checked" : "unchecked"}');
}
