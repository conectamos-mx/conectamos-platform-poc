// ADR-413 — Extracted relative-time helpers (pure functions).
// TZ handling preserved byte-identical from each original source.

/// "Ahora" / "Hace Xm" / "Hace Xh" / "Ayer" / "Hace X dias"
/// from ISO string. Applies `.toLocal()`.
///
/// [nullLabel] returned when [iso] is null ('—' for operators, 'Nunca' for catalogs).
/// [showSeconds] when true, shows "Hace Xs" for < 60s instead of "Ahora".
String fmtRelative(
  String? iso, {
  String nullLabel = '\u2014',
  bool showSeconds = false,
}) {
  if (iso == null) return nullLabel;
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
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
/// Naive — diffs against DateTime.now(), no TZ conversion.
String elapsedSince(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'hace ${d.inSeconds}s';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes}m';
  return 'hace ${d.inHours}h';
}
