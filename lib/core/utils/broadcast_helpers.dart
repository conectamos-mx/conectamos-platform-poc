// Pure helpers for broadcast template resolution and WhatsApp error parsing.
// Extracted from broadcast_screen.dart and conversations_screen.dart (PLA-67).

import 'package:intl/intl.dart';
import 'date_format.dart';
import 'tz_format.dart';

/// Standard free-text variable chips shown in the broadcast compose UI.
const kBroadcastFreeVars = [
  (key: '{nombre}', label: 'nombre'),
  (key: '{telefono}', label: 'teléfono'),
  (key: '{flujo}', label: 'flujo'),
  (key: '{hora}', label: 'hora'),
  (key: '{dia}', label: 'día'),
  (key: '{fecha}', label: 'fecha'),
  (key: '{tenant}', label: 'tenant'),
];

const _kTemplateExamples = <String, String>{
  'nombre_operador': 'José Miguel',
  'telefono_operador': '5215559537449',
  'nombre_tenant': 'TMR-Prixz',
  'fecha_hoy': '14/04/2026',
  'hora_actual': '10:30 AM',
};

/// Resolves a WhatsApp template body preview by replacing `{{N}}` slots
/// with example values based on the variable definitions.
///
/// - `type == 'system'` → uses [_kTemplateExamples] or `'[$key]'`
/// - `type != 'system'` (free) → `'[$key]'` if key is non-empty, else leaves `'{{$slot}}'`
/// - Unresolved slots remain as `{{N}}` literal.
String resolveTemplatePreview(Map<String, dynamic> template) {
  String preview = template['body_text']?.toString() ?? '';
  final vars = template['variables'];
  if (vars is List) {
    for (final v in vars) {
      if (v is! Map) continue;
      final slot = v['slot'] as int? ?? 0;
      final type = v['type'] as String? ?? 'free';
      final key = v['key'] as String? ?? '';
      final val = type == 'system'
          ? (_kTemplateExamples[key] ?? '[$key]')
          : (key.isNotEmpty ? '[$key]' : '{{$slot}}');
      if (slot > 0) preview = preview.replaceAll('{{$slot}}', val);
    }
  }
  return preview;
}

/// Produces a list of resolved variable values sorted by slot, suitable for
/// sending as `template_variables` in the broadcast API payload.
///
/// Uses the same system/free dispatch as [resolveTemplatePreview].
List<String> resolveTemplateVariables(Map<String, dynamic> template) {
  final vars = template['variables'];
  if (vars is! List || vars.isEmpty) return [];
  final sorted = vars
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList()
    ..sort((a, b) =>
        ((a['slot'] as int?) ?? 0).compareTo((b['slot'] as int?) ?? 0));
  return sorted.map((v) {
    final type = v['type'] as String? ?? 'free';
    final key = v['key'] as String? ?? '';
    if (type == 'system') return _kTemplateExamples[key] ?? '[$key]';
    return key.isNotEmpty ? '[$key]' : '[variable]';
  }).toList();
}

/// Maps known WhatsApp API error codes to user-friendly Spanish messages.
///
/// Recognises codes 131037 (display name) and 131026 (whitelist).
/// Falls back to a generic error string for anything else.
String parseWhatsAppErrorMessage(dynamic error) {
  try {
    final detail = error.toString();
    if (detail.contains('131037') || detail.contains('display name')) {
      return 'El número aún no tiene el nombre de perfil aprobado por Meta. '
          'Por favor espera la aprobación antes de iniciar nuevas conversaciones.';
    }
    if (detail.contains('131026') || detail.contains('not in whitelist')) {
      return 'Este número no está registrado como destinatario de prueba.';
    }
    return 'Error al enviar el mensaje. Intenta de nuevo.';
  } catch (_) {
    return 'Error al enviar el mensaje. Intenta de nuevo.';
  }
}

final _hhmmBcast = DateFormat('HH:mm');
final _slashDateBcast = DateFormat('dd/MM/yyyy');

/// Resolves broadcast free-text placeholders using tenant timezone.
///
/// Replaces {nombre}, {telefono}, {flujo}, {hora}, {dia}, {fecha}, {tenant}
/// with values from [op] and the active tenant timezone (via [nowInZone]).
///
/// When [now] is provided it is used as-is (assumed already in tenant zone);
/// when omitted, [nowInZone()] supplies the current tenant-local time.
String resolveFreeText(
    String text, Map<String, dynamic>? op, String tenantName,
    {DateTime? now}) {
  if (text.isEmpty) return text;
  now ??= nowInZone().now;
  String flowName = 'Sin flujo';
  if (op != null) {
    final flows = op['flows'];
    if (flows is List && flows.isNotEmpty) {
      final first = flows.first;
      flowName = first is Map
          ? (first['name']?.toString() ?? 'Sin flujo')
          : first.toString();
    }
  }
  return text
      .replaceAll(
          '{nombre}',
          op?['display_name']?.toString() ??
              op?['name']?.toString() ??
              'Operador')
      .replaceAll('{telefono}', op?['phone']?.toString() ?? '')
      .replaceAll('{flujo}', flowName)
      .replaceAll('{hora}', _hhmmBcast.format(now))
      .replaceAll('{dia}', fmtWeekdayEs(now))
      .replaceAll('{fecha}', _slashDateBcast.format(now))
      .replaceAll('{tenant}', tenantName);
}
