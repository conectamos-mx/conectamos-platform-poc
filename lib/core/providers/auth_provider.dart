import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'tenant_provider.dart';

// ── Mock ──────────────────────────────────────────────────────────────────────

/// Datos del usuario mock disponibles en toda la app.
class MockUser {
  const MockUser({
    required this.email,
    required this.tenant,
    required this.role,
  });
  final String email;
  final String tenant;
  final String role;
}

const kMockUser = MockUser(
  email: kMockEmail,
  tenant: kMockTenant,
  role: kMockRole,
);

// ── Providers reales (solo activos cuando kMockMode == false) ─────────────────

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  if (kMockMode) return null; // no se usa en mock
  ref.watch(authStateProvider); // invalidate on auth events so signedIn propagates
  final client = ref.watch(supabaseClientProvider);
  return client.auth.currentUser;
});

// ── Provider unificado de email (mock o real) ─────────────────────────────────

final currentUserEmailProvider = Provider<String>((ref) {
  if (kMockMode) return kMockUser.email;
  final user = ref.watch(currentUserProvider);
  return user?.email ?? '';
});

final currentTenantProvider = Provider<String>((ref) {
  if (kMockMode) return kMockUser.tenant;
  return ref.watch(activeTenantDisplayProvider);
});

// ── Super admin ───────────────────────────────────────────────────────────────

final isSuperAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.appMetadata['role'] == 'super_admin';
});
