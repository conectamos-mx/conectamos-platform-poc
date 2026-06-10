import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EscalacionesApi {
  static SupabaseClient get _sb => Supabase.instance.client;

  // ── REST ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getEscalaciones({
    required Dio dio,
    String? status,
    String? assignedTo,
  }) async {
    final params = <String, dynamic>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (assignedTo != null && assignedTo.isNotEmpty) {
      params['assigned_to'] = assignedTo;
    }
    final res = await dio.get(
      '/escalations',
      queryParameters: params,
    );
    final data = res.data;
    final List raw = data is List
        ? data
        : (data['escalations'] ?? data['items'] ?? []) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> patch(
    String id, {
    required Dio dio,
    required String action,
    String? assignedTo,
    String? resolutionNotes,
  }) async {
    final body = <String, dynamic>{'action': action};
    if (assignedTo != null) body['assigned_to'] = assignedTo;
    if (resolutionNotes != null) body['resolution_notes'] = resolutionNotes;
    await dio.patch('/escalations/$id', data: body);
  }

  // ── Supabase ──────────────────────────────────────────────────────────────

  /// Fetches wa_messages for the given list of UUIDs (trigger_messages).
  static Future<List<Map<String, dynamic>>> fetchTriggerMessages(
    List<String> ids, {
    required String tenantId,
  }) async {
    if (ids.isEmpty) return [];
    // Use OR filter: id=eq.uuid1,id=eq.uuid2,...
    final filter = ids.map((id) => 'id.eq.$id').join(',');
    final response = await _sb
        .from('wa_messages')
        .select('id, raw_body, direction, received_at, from_name, message_type')
        .or(filter)
        .eq('tenant_id', tenantId);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Realtime stream of open escalation count for the badge.
  static Stream<int> streamOpenCount({required String tenantId}) {
    return _sb
        .from('escalations')
        .stream(primaryKey: ['id'])
        .eq('tenant_id', tenantId)
        .map((rows) => rows.where((r) => r['status'] == 'open').length);
  }
}
