// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/tenants_api.dart';

// ── Modelo ────────────────────────────────────────────────────────────────────

class TenantInfo {
  const TenantInfo({
    required this.id,
    required this.slug,
    required this.displayName,
    this.logoUrl,
  });

  final String id;
  final String slug;
  final String displayName;
  final String? logoUrl;

  factory TenantInfo.fromMap(Map<String, dynamic> m) => TenantInfo(
        id: (m['id'] as String? ?? '').trim(),
        slug: m['slug'] as String? ?? '',
        displayName: m['display_name'] as String? ??
            m['name'] as String? ??
            m['slug'] as String? ??
            '',
        logoUrl: m['logo_url'] as String?,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class TenantState {
  const TenantState({this.all = const [], this.active});
  final List<TenantInfo> all;
  final TenantInfo? active;

  TenantState withActive(TenantInfo? t) => TenantState(all: all, active: t);
  TenantState withAll(List<TenantInfo> list, TenantInfo? t) =>
      TenantState(all: list, active: t);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class TenantNotifier extends StateNotifier<TenantState> {
  TenantNotifier() : super(const TenantState());

  static const _kStorageKey = 'conectamos_active_tenant_id';

  Future<void> load(String userEmail) async {
    if (state.all.isNotEmpty) return; // already loaded
    try {
      final supabaseUser = Supabase.instance.client.auth.currentUser;
      final userId = supabaseUser?.id;
      final isSuperAdmin = supabaseUser?.appMetadata['role'] == 'super_admin';
      final list = await TenantsApi.getTenants(
        userId: isSuperAdmin ? null : userId,
      );
      final tenants = list.map(TenantInfo.fromMap).toList();

      TenantInfo? active;

      // 1. Restore from localStorage if present and valid
      final savedId = (html.window.localStorage[_kStorageKey] ?? '').trim();
      if (savedId.isNotEmpty) {
        final matches = tenants.where((t) => t.id == savedId);
        if (matches.isNotEmpty) active = matches.first;
      }

      // 2. Fallback: tenants.first si no hay UUID guardado
      if (active == null && tenants.isNotEmpty) {
        active = tenants.first;
      }

      // Persist active tenant so ApiClient interceptor can read it
      if (active != null) {
        html.window.localStorage[_kStorageKey] = active.id;
      }
      state = state.withAll(tenants, active);
    } catch (_) {
      // silencioso — no bloquear la UI si falla la carga de tenants
    }
  }

  void select(TenantInfo tenant) {
    html.window.localStorage[_kStorageKey] = tenant.id;
    state = state.withActive(tenant);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final tenantNotifierProvider =
    StateNotifierProvider<TenantNotifier, TenantState>(
  (ref) => TenantNotifier(),
);

/// Tenant activo completo.
final activeTenantInfoProvider = Provider<TenantInfo?>((ref) {
  return ref.watch(tenantNotifierProvider).active;
});

/// UUID del tenant activo — para filtrar queries en Supabase y API.
final activeTenantIdProvider = Provider<String>((ref) {
  return ref.watch(activeTenantInfoProvider)?.id ?? '';
});

/// Display name del tenant activo — para mostrar en UI.
final activeTenantDisplayProvider = Provider<String>((ref) {
  return ref.watch(activeTenantInfoProvider)?.displayName ?? '';
});

/// Lista completa de tenants cargados.
final allTenantsProvider = Provider<List<TenantInfo>>((ref) {
  return ref.watch(tenantNotifierProvider).all;
});

/// Versión de estado de canales — incrementar tras toggle activo/inactivo para
/// notificar a pantallas dependientes (conversations, operators).
final channelStateVersionProvider = StateProvider<int>((ref) => 0);

/// Versión de estado de operadores — incrementar tras delete/restore para
/// notificar a la lista de operadores.
final operatorListVersionProvider = StateProvider<int>((ref) => 0);
