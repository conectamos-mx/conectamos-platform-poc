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

const _kTestToken = 'test-invite-token-abc';

const _kFakeInvitation = <String, dynamic>{
  'nombre': 'Ana García',
  'telefono': '+5215512345678',
  'email': 'ana@empresa.com',
  'tenant_name': 'Test Tenant',
  'role': {'id': 'role-1', 'name': 'Supervisor'},
};

const _kFakeRoles = [
  {'id': 'role-1', 'name': 'Supervisor'},
  {'id': 'role-2', 'name': 'Agente'},
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

  group('IAM invite → activate', () {
    testWidgets('invite dialog sends correct payload', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mock = MockApiInterceptor();
      mock.when('/iam/users', body: []);
      mock.when('/iam/roles', body: _kFakeRoles);
      mock.when('/iam/invite', body: null);
      _mockSupportingRoutes(mock);
      _initStaticApiClient(mock);

      await tester.pumpWidget(buildTestAppWithMock(mock));
      await tester.pumpAndSettle();

      // Navigate to /settings
      final scaffold = find.byType(Scaffold).first;
      GoRouter.of(tester.element(scaffold)).go('/settings');
      await tester.pumpAndSettle();

      // Tap "Usuarios" in the sidebar to show the users section
      final usersTab = find.text('Usuarios');
      expect(usersTab, findsOneWidget, reason: 'Usuarios tab should be in sidebar');
      await tester.tap(usersTab);
      await tester.pumpAndSettle();

      // Tap "Invitar usuario" button
      final inviteBtn = find.text('+ Invitar usuario');
      expect(inviteBtn, findsOneWidget, reason: 'Invite button should be visible');
      await tester.tap(inviteBtn);
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Invitar usuario'), findsWidgets);

      // Fill nombre
      final nameField = find.byKey(const Key('invite_name'));
      expect(nameField, findsOneWidget);
      final nameInput = find.descendant(
        of: nameField,
        matching: find.byType(TextField),
      );
      await tester.enterText(nameInput, 'Ana García');

      // Fill email
      final emailField = find.byKey(const Key('invite_email'));
      expect(emailField, findsOneWidget);
      await tester.enterText(emailField, 'ana@empresa.com');

      // Role dropdown should already have a value (first role auto-selected)
      final roleDropdown = find.byKey(const Key('invite_role'));
      expect(roleDropdown, findsOneWidget);

      // Tap submit
      final submitBtn = find.byKey(const Key('invite_submit'));
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify the mock captured POST /iam/invite
      final inviteCalls = mock.captured('/iam/invite');
      expect(inviteCalls, isNotEmpty, reason: 'Should have called POST /iam/invite');
      final inviteBody = inviteCalls.last.data as Map;
      expect(inviteBody['nombre'], 'Ana García');
      expect(inviteBody['email'], 'ana@empresa.com');
      expect(inviteBody['role_id'], 'role-1');

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'activate screen shows read-only data and sends only {password}',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mock = MockApiInterceptor();
        mock.when('/iam/invite/$_kTestToken', body: _kFakeInvitation);
        mock.when('/iam/invite/$_kTestToken/accept', body: null);
        _mockSupportingRoutes(mock);
        mock.when('/iam/users', body: []);
        mock.when('/iam/roles', body: _kFakeRoles);
        _initStaticApiClient(mock);

        await tester.pumpWidget(buildTestAppWithMock(mock));
        await tester.pumpAndSettle();

        // Navigate to /activate with token
        final scaffold = find.byType(Scaffold).first;
        GoRouter.of(tester.element(scaffold))
            .go('/activate?token=$_kTestToken');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Verify read-only nombre row
        final nameRow = find.byKey(const Key('activate_name'));
        expect(nameRow, findsOneWidget,
            reason: 'Read-only name should be visible');
        expect(
          find.descendant(of: nameRow, matching: find.text('Ana García')),
          findsOneWidget,
        );

        // Verify read-only phone row
        final phoneRow = find.byKey(const Key('activate_phone'));
        expect(phoneRow, findsOneWidget,
            reason: 'Read-only phone should be visible');
        expect(
          find.descendant(
              of: phoneRow, matching: find.text('+5215512345678')),
          findsOneWidget,
        );

        // Verify invite badge shows tenant + role
        expect(find.text('Test Tenant'), findsOneWidget);
        expect(find.text('Supervisor'), findsOneWidget);

        // Verify password fields are present and editable
        final passField = find.byKey(const Key('activate_password'));
        expect(passField, findsOneWidget);
        final passInput = find.descendant(
          of: passField,
          matching: find.byType(TextField),
        );
        await tester.enterText(passInput, 'SecurePass123');

        final confirmField = find.byKey(const Key('activate_confirm'));
        expect(confirmField, findsOneWidget);
        final confirmInput = find.descendant(
          of: confirmField,
          matching: find.byType(TextField),
        );
        await tester.enterText(confirmInput, 'SecurePass123');

        // Tap submit
        final submitBtn = find.byKey(const Key('activate_submit'));
        expect(submitBtn, findsOneWidget);
        await tester.tap(submitBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify POST /iam/invite/{token}/accept was called with ONLY {password}
        final acceptCalls =
            mock.captured('/iam/invite/$_kTestToken/accept');
        expect(acceptCalls, isNotEmpty,
            reason:
                'Should have called POST /iam/invite/{token}/accept');
        final acceptBody = acceptCalls.last.data as Map;
        expect(acceptBody, {'password': 'SecurePass123'},
            reason: 'Accept body should contain ONLY password');
        expect(acceptBody.containsKey('nombre'), isFalse,
            reason: 'Accept body should NOT contain nombre');
        expect(acceptBody.containsKey('telefono'), isFalse,
            reason: 'Accept body should NOT contain telefono');

        // Verify success widget
        final successBlock = find.byKey(const Key('activate_success'));
        expect(successBlock, findsOneWidget,
            reason:
                'Success block should be visible after activation');
        expect(find.text('Bienvenido a bordo'), findsOneWidget);

        // patrol_finders assertion
        final $ = PatrolTester(
          tester: tester,
          config: const PatrolTesterConfig(),
        );
        expect($('Bienvenido a bordo'), findsOneWidget);

        // Drain the 2-second delay timer from ActivateScreen success flow
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      },
    );
  });
}
