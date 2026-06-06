// ADR-413 + ADR-414 — Timezone-aware relative-time helpers.
// fmtRelative and elapsedSince use the global active zone via nowInZone/toZone.

import 'tz_format.dart';

/// "Ahora" / "Hace Xm" / "Hace Xh" / "Ayer" / "Hace X dias"
/// from ISO string. Both parsed date and "now" are in active tenant timezone.
///
/// [nullLabel] returned when [iso] is null.
/// [showSeconds] when true, shows "Hace Xs" for < 60s instead of "Ahora".
String fmtRelative(
  String? iso, {
  String nullLabel = '\u2014',
  bool showSeconds = false,
}) {
  if (iso == null) return nullLabel;
  try {
    final dt = DateTime.parse(iso);
    final tzR = toZone(dt);
    final nowR = nowInZone();
    final diff = nowR.now.difference(tzR.dt);
    if (showSeconds) {
      if (diff.inSeconds < 60) return 'Hace ${diff.inSeconds}s';
    } else {
      if (diff.inMinutes < 1) return 'Ahora';
    }
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'Ayer';
    return 'Hace ${diff.inDays} d\u00edas';
  } catch (_) {
    return '\u2014';
  }
}

/// "Xs" / "Xm Xs" / "Xh Xm" from elapsed seconds. No TZ involved.
String fmtElapsedSeconds(int? seconds) {
  if (seconds == null) return '\u2014';
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

/// "hace Xs" / "hace Xm" / "hace Xh" from DateTime.
/// Uses nowInZone for "now" in active tenant timezone.
String elapsedSince(DateTime t) {
  final nowR = nowInZone();
  final d = nowR.now.difference(t);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds}s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes}m';
  return 'hace ${d.inHours}h';
}
