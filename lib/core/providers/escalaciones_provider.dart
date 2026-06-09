import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/escalaciones_api.dart';
import 'tenant_provider.dart';

/// Badge numérico — count de escalaciones con status='open' vía Supabase Realtime.
final openEscalationsCountProvider = StreamProvider.autoDispose<int>((ref) {
  final tenantId = ref.watch(activeTenantIdProvider);
  if (tenantId.isEmpty) return Stream.value(0);
  return EscalacionesApi.streamOpenCount(tenantId: tenantId);
});

/// Lista de usuarios del tenant para el dropdown de asignación.
final tenantUsersForEscalacionesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final tenantId = ref.watch(activeTenantIdProvider);
  if (tenantId.isEmpty) return [];
  final res = await ref.read(apiClientProvider).dio.get('/iam/users');
  final data = res.data;
  final List raw = data is List
      ? data
      : (data['users'] ?? data['items'] ?? []) as List;
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
