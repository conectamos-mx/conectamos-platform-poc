/// Helpers para parsing y formato de scope/window de assignments.
///
/// El scope es un range literal de PostgreSQL: "[lo,hi)" con timestamps ISO-8601.
library;

import 'package:intl/intl.dart';

final _dateFmt = DateFormat('d MMM', 'es_MX');
final _timeFmt = DateFormat('HH:mm');
final _dtFmt   = DateFormat('d MMM HH:mm', 'es');

/// Parsea un range literal de PostgreSQL "[lo,hi)" a un par de DateTime.
/// Malformado / null / empty -> (null, null). Nunca throw.
/// TZ: preserva la zona del string (si tiene Z -> UTC, si no -> local).
(DateTime?, DateTime?) parseScope(String? raw) {
  if (raw == null || raw.isEmpty) return (null, null);
  try {
    final clean = raw
        .replaceAll('"', '')
        .replaceAll('[', '')
        .replaceAll('(', '')
        .replaceAll(']', '')
        .replaceAll(')', '');
    final parts = clean.split(',');
    if (parts.length < 2) return (null, null);
    final lower = parts[0].trim();
    final upper = parts[1].trim();
    if (lower.isEmpty || upper.isEmpty) return (null, null);
    return (DateTime.parse(lower), DateTime.parse(upper));
  } catch (_) {
    return (null, null);
  }
}

/// Formatea un scope para display con logica same-day:
/// mismo dia: "5 jun · 09:00 - 17:00"
/// distinto dia: "5 jun 09:00 - 6 jun 17:00"
/// Malformado -> "-".
String formatWindow(String? raw) {
  final (lo, hi) = parseScope(raw);
  if (lo == null || hi == null) return '\u2014';
  final loL = lo.toLocal();
  final hiL = hi.toLocal();
  final sameDay = loL.year == hiL.year &&
      loL.month == hiL.month &&
      loL.day == hiL.day;
  if (sameDay) {
    return '${_dateFmt.format(loL)} \u00b7 ${_timeFmt.format(loL)} \u2013 ${_timeFmt.format(hiL)}';
  }
  return '${_dateFmt.format(loL)} ${_timeFmt.format(loL)} \u2013 '
      '${_dateFmt.format(hiL)} ${_timeFmt.format(hiL)}';
}

/// Formatea un scope sin logica same-day: siempre "d MMM HH:mm - d MMM HH:mm".
/// Malformado -> "-".
String formatScopeCompact(String? raw) {
  final (lo, hi) = parseScope(raw);
  if (lo == null || hi == null) return '\u2014';
  return '${_dtFmt.format(lo.toLocal())} \u2013 ${_dtFmt.format(hi.toLocal())}';
}
