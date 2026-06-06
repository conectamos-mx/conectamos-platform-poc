// ADR-413 + ADR-414 — Timezone-aware relative-time helpers.
// fmtRelative is the single canonical relative-time formatter.
// Always uses toZone()/nowInZone() for tenant timezone.

import 'package:intl/intl.dart';
import 'tz_format.dart';

final _absDate = DateFormat('dd/MM/yyyy');

/// Canonical relative-time formatter.
///
/// "Ahora" / "Hace X min" / "Hace Xh" / "Ayer" / "Hace X días"
/// from ISO string. Both parsed date and "now" are in tenant timezone.
///
/// [nullLabel] returned when [iso] is null.
/// [showSeconds] when true, shows "Hace Xs" for < 60s instead of "Ahora".
/// [compact] when true, uses lowercase abbreviated form: "ahora"/"hace Xm"/"hace Xh"/"ayer"/"hace Xd".
/// [absoluteAfterDays] when set, returns absolute date "dd/MM/yyyy" if diff > N days.
String fmtRelative(
  String? iso, {
  String nullLabel = '\u2014',
  bool showSeconds = false,
  bool compact = false,
  int? absoluteAfterDays,
}) {
  if (iso == null) return nullLabel;
  try {
    final dt = DateTime.parse(iso);
    final tzR = toZone(dt);
    final nowR = nowInZone();
    final diff = nowR.now.difference(tzR.dt);

    if (absoluteAfterDays != null && diff.inDays > absoluteAfterDays) {
      return _absDate.format(tzR.dt);
    }

    if (compact) {
      if (showSeconds) {
        if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
      } else {
        if (diff.inMinutes < 1) return 'ahora';
      }
      if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
      if (diff.inHours < 24) return 'hace ${diff.inHours}h';
      if (diff.inDays == 1) return 'ayer';
      return 'hace ${diff.inDays}d';
    }

    // Default: Title-case verbose
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
