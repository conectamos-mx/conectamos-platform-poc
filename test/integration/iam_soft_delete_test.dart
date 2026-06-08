@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:conectamos_platform/core/api/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/in_memory_key_value_store.dart';
import 'helpers/mock_api_interceptor.dart';
import 'helpers/test_overrides.dart';

const _kUserId = 'user-abc-123';

final _kFakeUser = <String, dynamic>{
  'id': _kUserId,
  'name': 'María López',
  'email': 'maria@empresa.com',
  'telefono': '+5215500001111',
  'role_id': 'role-1',
  'status': 'active',
};

const _kFakeRoles = [
  {'id': 'role-1', 'name': 'Supervisor'},
];

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
}

void main() {
  setUpAll(() => initTestLocale());

  group('IAM soft-delete user', () {
    testWidgets(
      'delete user → row disappears from list after refetch',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Mutable user list: starts with 1 user, becomes empty after delete.
        final userList = <Map<String, dynamic>>[Map.of(_kFakeUser)];

        final mock = MockApiInterceptor();
        // GET /iam/users returns the mutable list (refetch sees updated state).
        mock.when('/iam/users', body: userList);
        mock.when('/iam/roles', body: _kFakeRoles);
        // DELETE /iam/users/{id} succeeds.
        mock.when('/iam/users/{id}', method: 'DELETE', body: null);
        _mockSupportingRoutes(mock);
        _initStaticApiClient(mock);

        await tester.pumpWidget(buildTestAppWithMock(mock));
        await tester.pumpAndSettle();

        // Navigate to /settings
        final scaffold = find.byType(Scaffold).first;
        GoRouter.of(tester.element(scaffold)).go('/settings');
        await tester.pumpAndSettle();

        // Switch to "Usuarios" section
        await tester.tap(find.text('Usuarios'));
        await tester.pumpAndSettle();

        // Verify user row is visible
        final userRow = find.byKey(const ValueKey('user_row_$_kUserId'));
        expect(userRow, findsOneWidget,
            reason: 'User row should be visible before delete');
        expect(find.text('María López'), findsOneWidget);

        // Open PopupMenu on the user row (tap the ⋮ icon)
        final menuIcon = find.descendant(
          of: userRow,
          matching: find.byIcon(Icons.more_vert_rounded),
        );
        expect(menuIcon, findsOneWidget);
        await tester.tap(menuIcon);
        await tester.pumpAndSettle();

        // Tap "Eliminar" in the popup menu
        final deleteMenuItem =
            find.byKey(const Key('user_delete_menu_$_kUserId'));
        expect(deleteMenuItem, findsOneWidget);
        await tester.tap(deleteMenuItem);
        await tester.pumpAndSettle();

        // Confirm dialog is shown
        expect(find.text('Eliminar usuario'), findsOneWidget);
        expect(find.text('¿Eliminar a María López?'), findsOneWidget);

        // Before confirming, clear the user list to simulate backend
        // returning filtered results on refetch (deleted_at is set).
        userList.clear();

        // Tap confirm "Eliminar" button
        final confirmBtn = find.byKey(const Key('user_delete_confirm'));
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        // Verify DELETE was sent to /iam/users/{id}
        final deleteCalls =
            mock.captured('/iam/users/{id}', method: 'DELETE');
        expect(deleteCalls, isNotEmpty,
            reason: 'Should have sent DELETE /iam/users/{id}');
        expect(deleteCalls.last.path, '/iam/users/$_kUserId');

        // Verify the user row is GONE after refetch
        expect(
          find.byKey(const ValueKey('user_row_$_kUserId')),
          findsNothing,
          reason: 'User row should disappear after delete + refetch',
        );
        expect(find.text('María López'), findsNothing);

        // Verify empty state message
        expect(
          find.text('No hay usuarios registrados en este tenant.'),
          findsOneWidget,
          reason: 'Empty state should show when no users remain',
        );

        // patrol_finders assertion
        final $ = PatrolTester(
          tester: tester,
          config: const PatrolTesterConfig(),
        );
        expect(
          $('No hay usuarios registrados en este tenant.'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}
