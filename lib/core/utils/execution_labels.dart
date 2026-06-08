// Pure label/transform helpers for flow-execution data.
// Extracted from execution_export.dart and all_executions_screen.dart (PLA-68).

/// Human-readable label for an execution event type.
String executionEventLabel(String type) => switch (type) {
      'flujo_iniciado' => 'Flujo iniciado',
      'flujo_completado' => 'Flujo completado',
      'flujo_retomado' => 'Flujo retomado',
      'campo_capturado' => 'Campo capturado',
      'campo_rechazado' => 'Campo rechazado',
      'worker_escaló' => 'Worker escaló',
      'flujo_abandonado' => 'Flujo abandonado',
      'supervisor_intervino' => 'Supervisor intervino',
      'flujo_pausado' => 'Flujo pausado',
      _ => type,
    };

/// Canonical Spanish label for an execution status key.
///
/// Unifies the status maps previously in execution_export.dart and
/// all_executions_screen.dart into a single superset (masculine gender).
String executionStatusLabel(String s) => switch (s) {
      'completed' => 'Completado',
      'in_progress' || 'active' => 'En curso',
      'pending' => 'Pendiente',
      'pending_dashboard' || 'pending_review' => 'Pendiente de revisión',
      'paused' => 'Pausado',
      'abandoned' => 'Abandonado',
      'escalated' => 'Escalado',
      'cancelled' => 'Cancelado',
      'failed' || 'error' => 'Fallido',
      _ => s,
    };

/// Groups a pre-sorted list of execution events by consecutive runs of the
/// same `type` (or `event_type`) key.
List<({String type, List<Map<String, dynamic>> items})> groupExecutionEvents(
    List<Map<String, dynamic>> sorted) {
  final groups = <({String type, List<Map<String, dynamic>> items})>[];
  for (final e in sorted) {
    final type = e['type'] as String? ?? e['event_type'] as String? ?? '';
    if (groups.isNotEmpty && groups.last.type == type) {
      groups.last.items.add(e);
    } else {
      groups.add((type: type, items: [e]));
    }
  }
  return groups;
}

/// Extracts a display-ready value from a field-value map, dispatching on [type].
///
/// Branches:
/// - `number` → `value_numeric`
/// - `media` / `photo` → `value_jsonb['url']` or `value_media_url`
/// - `location` → `value_jsonb` lat/lng pair or `value_text`
/// - anything else → `value_text`
///
/// Returns `'—'` when no value is found.
String resolveFieldValue(Map<String, dynamic> fv, String type) {
  switch (type) {
    case 'number':
      return fv['value_numeric']?.toString() ?? '—';
    case 'media':
    case 'photo':
      final jsonb = fv['value_jsonb'];
      if (jsonb is Map) return jsonb['url']?.toString() ?? '—';
      return fv['value_media_url']?.toString() ?? '—';
    case 'location':
      final jsonb = fv['value_jsonb'];
      if (jsonb is Map) {
        final lat = jsonb['lat'] ?? jsonb['latitude'];
        final lng = jsonb['lng'] ?? jsonb['longitude'];
        if (lat != null && lng != null) return '$lat, $lng';
      }
      return fv['value_text']?.toString() ?? '—';
    default:
      return fv['value_text']?.toString() ?? '—';
  }
}
