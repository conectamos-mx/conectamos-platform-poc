import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config.dart';
import 'auth_provider.dart';
import 'tenant_provider.dart';

// ── Conjunto de todos los permisos disponibles ────────────────────────────────

const _kAllPermissions = {
  'conversations.view', 'conversations.send', 'conversations.export',
  'broadcasts.send',
  'flows.view', 'flows.manage',
  'flow_executions.execute_dashboard', 'flow_executions.view_all',
  'flow_integrations.view', 'flow_integrations.manage',
  'operators.view', 'operators.manage',
  'escalations.view', 'escalations.manage',
  'reports.view',
  'settings.view', 'settings.manage',
  'users.view', 'users.manage',
  'dashboards.view', 'dashboards.manage',
  'catalogs.view', 'catalogs.manage',
};

// ── Rol del usuario autenticado en el tenant activo ───────────────────────────

final userRoleProvider = FutureProvider.autoDispose<String?>((ref) async {
  if (kMockMode) return kMockUser.role;
  // Bypass para super_admin — sin llamada a GET /iam/users
  if (ref.watch(isSuperAdminProvider)) return 'super_admin';
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  // BUG 1: esperar a que activeTenantIdProvider tenga valor antes de llamar al backend
  final tenantId = ref.watch(activeTenantIdProvider);
  if (tenantId.isEmpty) return null;
  final res = await ApiClient.instance.get('/iam/users');
  final data = res.data;
  final List raw = data is List
      ? data
      : (data['users'] ?? data['items'] ?? []) as List;
  final users = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (users.isNotEmpty) {
    debugPrint('[userRoleProvider] primer usuario: ${users.first}');
  }
  final match = users.firstWhere(
    (u) =>
        (u['user_id']          as String?) == user.id ||
        (u['id']               as String?) == user.id ||
        (u['supabase_user_id'] as String?) == user.id ||
        (u['email']            as String?) == user.email,
    orElse: () => {},
  );
  if (match.isEmpty) {
    debugPrint('[userRoleProvider] no se encontró match para id=${user.id} email=${user.email}');
    return null;
  }
  // BUG 2: leer roles.name como primera opción, con fallback a role
  final rolesField = match['roles'];
  if (rolesField is Map) return rolesField['name'] as String?;
  final roleField = match['role'];
  if (roleField is Map) return roleField['name'] as String?;
  return roleField as String?;
});

// ── Set de permisos del usuario (admin → todos sin API call) ──────────────────

final userPermissionsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  if (kMockMode) return _kAllPermissions;
  // Bypass para super_admin — sin llamadas a IAM
  if (ref.watch(isSuperAdminProvider)) return _kAllPermissions;
  final role = await ref.watch(userRoleProvider.future);
  if (role == null) return {};
  if (role.toLowerCase() == 'admin') return _kAllPermissions;

  // Buscar role_id por nombre
  final rolesRes = await ApiClient.instance.get('/iam/roles');
  final rolesData = rolesRes.data;
  final List rawRoles = rolesData is List
      ? rolesData
      : (rolesData['roles'] ?? rolesData['items'] ?? []) as List;
  final roles = rawRoles.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final roleEntry = roles.firstWhere(
    (r) => (r['name'] as String?)?.toLowerCase() == role.toLowerCase(),
    orElse: () => {},
  );
  if (roleEntry.isEmpty) return {};
  final roleId = roleEntry['id'] as String? ?? '';
  if (roleId.isEmpty) return {};

  // Obtener permisos del rol
  final permRes = await ApiClient.instance.get('/iam/roles/$roleId/permissions');
  final permData = permRes.data;
  final List rawPerms = permData is List
      ? permData
      : (permData['permissions'] ?? permData['items'] ?? []) as List;
  return rawPerms
      .map((e) => Map<String, dynamic>.from(e as Map))
      .where((p) => p['granted'] == true || p['enabled'] == true)
      .map((p) => p['permission'] as String? ?? p['name'] as String? ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();
});

// ── Helper síncrono para widgets ──────────────────────────────────────────────

/// Devuelve true si el usuario tiene el permiso `module.action`.
/// Usa ref.watch → el widget se reconstruye cuando los permisos cargan.
/// Solo llamar desde dentro de un build() de ConsumerWidget o ConsumerState.
bool hasPermission(WidgetRef ref, String module, String action) {
  return ref
          .watch(userPermissionsProvider)
          .valueOrNull
          ?.contains('$module.$action') ??
      false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Editor de permisos por rol
// ═══════════════════════════════════════════════════════════════════════════

// ── Modelo de rol ─────────────────────────────────────────────────────────────

class Role {
  const Role({required this.id, required this.name});
  final String id;
  final String name;
}

// ── Lista de roles del tenant ─────────────────────────────────────────────────

final roleListProvider = FutureProvider.autoDispose<List<Role>>((ref) async {
  if (kMockMode) {
    return const [
      Role(id: 'admin-mock',      name: 'admin'),
      Role(id: 'supervisor-mock', name: 'supervisor'),
      Role(id: 'viewer-mock',     name: 'viewer'),
    ];
  }
  final res = await ApiClient.instance.get('/iam/roles');
  final data = res.data;
  final List raw = data is List
      ? data
      : (data['roles'] ?? data['items'] ?? []) as List;
  return raw
      .map((e) => Map<String, dynamic>.from(e as Map))
      .map((m) => Role(
            id: m['id'] as String? ?? '',
            name: (m['name'] as String? ?? '').toLowerCase(),
          ))
      .where((r) => r.id.isNotEmpty)
      .toList();
});

// ── Labels legibles ───────────────────────────────────────────────────────────

const kPermLabels = <String, String>{
  'conversations.view':   'Ver conversaciones',
  'conversations.send':   'Enviar mensajes',
  'conversations.export': 'Exportar conversaciones',
  'broadcasts.send':      'Enviar broadcasts',
  'flows.view':           'Ver flujos',
  'flows.manage':         'Gestionar flujos',
  'flow_executions.execute_dashboard': 'Ejecutar tareas del dashboard',
  'flow_executions.view_all':          'Ver todas las ejecuciones',
  'flow_integrations.view':            'Ver integraciones de flows',
  'flow_integrations.manage':          'Gestionar integraciones de flows',
  'operators.view':       'Ver operadores',
  'operators.manage':     'Gestionar operadores',
  'escalations.view':     'Ver escalaciones',
  'escalations.manage':   'Gestionar escalaciones',
  'reports.view':         'Ver reportes',
  'settings.view':        'Ver configuración',
  'settings.manage':      'Gestionar configuración',
  'users.view':           'Ver usuarios',
  'users.manage':         'Gestionar usuarios',
  'dashboards.view':      'Ver dashboards',
  'dashboards.manage':    'Gestionar dashboards',
  'catalogs.view':        'Ver catálogos',
  'catalogs.manage':      'Gestionar catálogos',
  'webhook_secrets.view': 'Ver webhook secrets',
};

// ── Prerequisitos ─────────────────────────────────────────────────────────────

const _kPrerequisites = <String, String>{
  'conversations.send':   'conversations.view',
  'conversations.export': 'conversations.view',
  'broadcasts.send':      'conversations.view',
  'flows.manage':         'flows.view',
  'operators.manage':     'operators.view',
  'escalations.manage':   'escalations.view',
  'settings.manage':      'settings.view',
  'users.manage':         'users.view',
  'catalogs.manage':      'catalogs.view',
};

// ── Estado del editor ─────────────────────────────────────────────────────────

class RolePermState {
  const RolePermState({
    required this.grants,
    required this.initialGrants,
    required this.permIds,
    required this.loading,
    this.error,
  });

  final Map<String, bool>   grants;
  final Map<String, bool>   initialGrants;
  final Map<String, String> permIds; // 'module.action' → uuid
  final bool                loading;
  final String?             error;

  bool get hasPendingChanges {
    for (final key in grants.keys) {
      if ((grants[key] ?? false) != (initialGrants[key] ?? false)) return true;
    }
    return false;
  }

  RolePermState copyWith({
    Map<String, bool>?   grants,
    Map<String, bool>?   initialGrants,
    Map<String, String>? permIds,
    bool?                loading,
    String?              error,
    bool                 clearError = false,
  }) {
    return RolePermState(
      grants:        grants        ?? this.grants,
      initialGrants: initialGrants ?? this.initialGrants,
      permIds:       permIds       ?? this.permIds,
      loading:       loading       ?? this.loading,
      error:         clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class RolePermissionsNotifier extends StateNotifier<RolePermState> {
  RolePermissionsNotifier(this._roleId)
      : super(const RolePermState(
          grants:        {},
          initialGrants: {},
          permIds:       {},
          loading:       true,
        )) {
    _load();
  }

  final String _roleId;

  Future<void> _load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res  = await ApiClient.instance.get('/iam/roles/$_roleId/permissions');
      final data = res.data;
      final List raw = data is List
          ? data
          : (data['permissions'] ?? data['items'] ?? []) as List;
      final grants  = <String, bool>{};
      final permIds = <String, String>{};
      for (final raw0 in raw) {
        final p      = Map<String, dynamic>.from(raw0 as Map);
        final module = p['module'] as String? ?? '';
        final action = p['action'] as String? ?? '';
        final id     = p['id']     as String? ?? '';
        final granted = p['granted'] as bool? ?? false;
        if (module.isNotEmpty && action.isNotEmpty) {
          final key   = '$module.$action';
          grants[key] = granted;
          if (id.isNotEmpty) permIds[key] = id;
        }
      }
      state = state.copyWith(
        grants:        grants,
        initialGrants: Map.from(grants),
        permIds:       permIds,
        loading:       false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Toggles a permission and returns cascade description strings (for toast).
  List<String> toggle(String module, String action) {
    final key     = '$module.$action';
    final current = state.grants[key] ?? false;
    final newGrants = Map<String, bool>.from(state.grants);
    final cascades  = <String>[];

    if (!current) {
      // Activating: also activate prerequisite if needed
      newGrants[key] = true;
      final prereq = _kPrerequisites[key];
      if (prereq != null && !(newGrants[prereq] ?? false)) {
        newGrants[prereq] = true;
        cascades.add(
          'Se activó también "${kPermLabels[prereq] ?? prereq}" '
          'porque es requerido por "${kPermLabels[key] ?? key}".',
        );
      }
    } else {
      // Deactivating: also deactivate dependents
      newGrants[key] = false;
      for (final entry in _kPrerequisites.entries) {
        if (entry.value == key && (newGrants[entry.key] ?? false)) {
          newGrants[entry.key] = false;
          cascades.add(
            'Se desactivó también "${kPermLabels[entry.key] ?? entry.key}" '
            'porque requiere "${kPermLabels[key] ?? key}".',
          );
        }
      }
    }

    state = state.copyWith(grants: newGrants);
    return cascades;
  }

  /// Saves diff to backend. Returns null on success or an error message.
  Future<String?> save() async {
    final grant  = <String>[];
    final revoke = <String>[];
    for (final key in state.grants.keys) {
      final current = state.grants[key]        ?? false;
      final initial = state.initialGrants[key] ?? false;
      final id      = state.permIds[key];
      if (id == null) continue;
      if (current && !initial) grant.add(id);
      if (!current && initial) revoke.add(id);
    }
    if (grant.isEmpty && revoke.isEmpty) return null;
    try {
      await ApiClient.instance.patch(
        '/iam/roles/$_roleId/permissions',
        data: {'grant': grant, 'revoke': revoke},
      );
      state = state.copyWith(initialGrants: Map.from(state.grants));
      return null;
    } catch (e) {
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          final code = body['error'] as String?;
          if (code == 'admin_role_immutable') {
            return 'El rol admin no puede modificarse.';
          }
          if (code == 'prerequisite_violation') {
            return body['message'] as String? ?? 'Error de prerequisito.';
          }
          final detail = body['detail'];
          if (detail != null) return detail.toString();
        }
      }
      return e.toString();
    }
  }
}

final rolePermissionsEditProvider = StateNotifierProvider.autoDispose
    .family<RolePermissionsNotifier, RolePermState, String>(
  (ref, roleId) => RolePermissionsNotifier(roleId),
);
