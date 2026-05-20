import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../providers/permissions_provider.dart';
import '../../features/auth/activate_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/broadcasts/broadcast_screen.dart';
import '../../features/config/channels_screen.dart';
import '../../features/config/connections_screen.dart';
import '../../features/config/operator_detail_screen.dart';
import '../../features/config/operator_roles_screen.dart';
import '../../features/config/operators_screen.dart';
import '../../features/config/settings_screen.dart';
import '../../features/settings/operator_fields_screen.dart';
import '../../features/config/ai_workers_screen.dart';
import '../../features/config/worker_detail_screen.dart';
import '../../features/config/workflows_screen.dart';
import '../../features/assignments/assignments_screen.dart';
import '../../features/assignments/assignment_detail_screen.dart';
import '../../features/catalogs/catalog_detail_screen.dart';
import '../../features/catalogs/catalogs_screen.dart';
import '../../features/flows/all_executions_screen.dart';
import '../../features/flows/executions_screen.dart';
import '../../features/flows/execution_detail_screen.dart';
import '../../features/flows/flow_detail_screen.dart';
import '../../features/conversations/conversations_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/escalaciones/escalaciones_screen.dart';
import '../../features/overview/overview_screen.dart';
import '../../shared/widgets/app_shell.dart';

// Mapa de ruta → permiso requerido
const _kRoutePermissions = {
  '/operators':    'operators.view',
  '/connections':  'settings.view',
  '/settings':     'settings.view',
  '/workers':      'settings.manage',
  '/catalogs':     'catalogs.view',
  '/assignments':  'assignments.view',
  '/broadcast':    'broadcasts.send',
  '/escalaciones': 'escalations.view',
};

final routerProvider = Provider<GoRouter>((ref) {
  // Refresca el router cuando cargan los permisos o cambia el estado de auth
  final refresher = ValueNotifier<int>(0);
  ref.listen(userPermissionsProvider, (prev, next) => refresher.value++);
  final authSub = Supabase.instance.client.auth.onAuthStateChange
      .listen((_) => refresher.value++);
  ref.onDispose(authSub.cancel);

  // Preserva la ruta destino al redirigir al login en deep-link / reload
  String? pendingRedirect;

  return GoRouter(
    initialLocation: '/overview',
    refreshListenable: refresher,
    redirect: (context, state) {
      if (kMockMode) {
        if (state.matchedLocation == '/login') return null;
        if (state.matchedLocation == '/overview') return null;
        if (state.matchedLocation == '/') return '/overview';
        return '/overview';
      }

      final user = Supabase.instance.client.auth.currentUser;
      final loc = state.matchedLocation;
      final isLoggingIn = loc == '/login';
      final isActivating = loc.startsWith('/activate');
      final isPublicAuth = loc == '/forgot-password' || loc.startsWith('/reset-password');

      // Rutas de auth públicas
      if (isActivating || isPublicAuth) return null;

      // Redirect bare / to /overview
      if (loc == '/') return '/overview';

      if (user == null && !isLoggingIn) {
        // Guardar la ruta destino para restaurarla después del login
        if (loc != '/overview') pendingRedirect = state.uri.toString();
        return '/login';
      }
      if (user != null && isLoggingIn) {
        // Si hay ruta pendiente (deep-link en reload), restaurarla
        final dest = pendingRedirect;
        pendingRedirect = null;
        return dest ?? '/overview';
      }

      // Guard de permisos (solo cuando ya cargaron)
      final perms = ref.read(userPermissionsProvider).valueOrNull;
      if (perms != null) {
        for (final entry in _kRoutePermissions.entries) {
          if (loc.startsWith(entry.key) && !perms.contains(entry.value)) {
            return '/overview';
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/activate',
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return NoTransitionPage(child: ActivateScreen(token: token));
        },
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ForgotPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return NoTransitionPage(child: ResetPasswordScreen(token: token));
        },
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) => NoTransitionPage(
          child: AppShell(navigationShell: navigationShell),
        ),
        branches: [
          // Branch 0 — Overview
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/overview',
              pageBuilder: (c, s) => const NoTransitionPage(child: OverviewScreen()),
            ),
          ]),
          // Branch 1 — Conversations
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/conversations',
              pageBuilder: (c, s) => const NoTransitionPage(child: ConversationsScreen()),
            ),
          ]),
          // Branch 2 — Broadcast
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/broadcast',
              pageBuilder: (c, s) => const NoTransitionPage(child: BroadcastScreen()),
            ),
          ]),
          // Branch 3 — Dashboard
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (c, s) => const NoTransitionPage(child: DashboardScreen()),
            ),
          ]),
          // Branch 4 — Operators
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/operators',
              pageBuilder: (c, s) => const NoTransitionPage(child: OperatorsScreen()),
              routes: [
                GoRoute(
                  path: 'roles',
                  pageBuilder: (c, s) => const NoTransitionPage(child: OperatorRolesScreen()),
                ),
                GoRoute(
                  path: ':id',
                  pageBuilder: (c, s) => NoTransitionPage(
                    child: OperatorDetailScreen(operatorId: s.pathParameters['id'] ?? ''),
                  ),
                ),
              ],
            ),
          ]),
          // Branch 5 — Executions
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/executions',
              pageBuilder: (c, s) => const NoTransitionPage(child: AllExecutionsScreen()),
              routes: [
                GoRoute(
                  path: ':executionId',
                  pageBuilder: (c, s) {
                    final executionId = s.pathParameters['executionId'] ?? '';
                    return NoTransitionPage(
                      key: ValueKey(executionId),
                      child: ExecutionDetailScreen(executionId: executionId),
                    );
                  },
                ),
              ],
            ),
          ]),
          // Branch 6 — Tareas
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/tareas',
              pageBuilder: (c, s) => const NoTransitionPage(child: ExecutionsScreen()),
            ),
          ]),
          // Branch 7 — Escalaciones
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/escalaciones',
              pageBuilder: (c, s) => const NoTransitionPage(child: EscalacionesScreen()),
            ),
          ]),
          // Branch 8 — Workers
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/workers',
              pageBuilder: (c, s) => const NoTransitionPage(child: AiWorkersScreen()),
              routes: [
                GoRoute(
                  path: ':workerId',
                  pageBuilder: (c, s) => NoTransitionPage(
                    child: WorkerDetailScreen(
                      workerId: s.pathParameters['workerId'] ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ]),
          // Branch 9 — Connections
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/connections',
              pageBuilder: (c, s) => const NoTransitionPage(child: ConnectionsScreen()),
            ),
          ]),
          // Branch 10 — Settings
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (c, s) => const NoTransitionPage(child: SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'operator-fields',
                  pageBuilder: (c, s) => const NoTransitionPage(child: OperatorFieldsScreen()),
                ),
              ],
            ),
          ]),
          // Branch 11 — Catalogs
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/catalogs',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: CatalogsScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':catalogSlug',
                  pageBuilder: (context, state) {
                    final slug = state.pathParameters['catalogSlug'] ?? '';
                    return NoTransitionPage(
                      child: CatalogDetailScreen(slug: slug),
                    );
                  },
                ),
              ],
            ),
          ]),
          // Branch 12 — Assignments
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/assignments',
              pageBuilder: (c, s) => const NoTransitionPage(child: AssignmentsScreen()),
              routes: [
                GoRoute(
                  path: ':assignmentId',
                  pageBuilder: (c, s) => NoTransitionPage(
                    child: AssignmentDetailScreen(
                      assignmentId: s.pathParameters['assignmentId'] ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ]),
        ],
      ),
      // Standalone routes — accessible without shell (deep links)
      GoRoute(
        path: '/flows',
        pageBuilder: (c, s) => const NoTransitionPage(child: WorkflowsScreen()),
      ),
      GoRoute(
        path: '/flows/:flowId',
        pageBuilder: (c, s) => NoTransitionPage(
          child: FlowDetailScreen(flowId: s.pathParameters['flowId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/channels',
        pageBuilder: (c, s) => const NoTransitionPage(child: ChannelsScreen()),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Página no encontrada: ${state.error}'),
      ),
    ),
  );
});
