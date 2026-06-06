// ADR-413 + ADR-414 — Timezone-aware date/time formatting helpers.
// All functions delegate to the global active zone in tz_format.dart.
// Fallback on invalid zone: UTC + visible "(UTC)" marker — NEVER silent.

import 'package:intl/intl.dart';
import 'tz_format.dart';

// ── Shared DateFormat instances ──────────────────────────────────────────────

final _hhmm = DateFormat('HH:mm');
final _ddMmmHm = DateFormat("dd MMM '\u00b7' HH:mm", 'es_MX');
final _ddMmmHms = DateFormat("dd MMM '\u00b7' HH:mm:ss", 'es_MX');
final _slashFull = DateFormat('dd/MM/yyyy HH:mm');
final _slashDate = DateFormat('dd/MM/yyyy');
final _slashCompact = DateFormat('dd/MM HH:mm');
final _heroFmt = DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'es_MX');
final _dMmm = DateFormat('d MMM', 'es_MX');
final _ddMm = DateFormat('dd/MM');

// ── Absolute format: ISO string → localised string ──────────────────────────

/// "HH:mm" from ISO string in active tenant timezone.
/// [fallback] returned on null or parse error.
String fmtTime(String? iso, {String fallback = '\u2014'}) {
  if (iso == null) return fallback;
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _hhmm).text;
  } catch (_) {
    return fallback;
  }
}

/// "dd MMM · HH:mm" from ISO string in active tenant timezone.
String fmtDateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '\u2014';
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _ddMmmHm).text;
  } catch (_) {
    return iso;
  }
}

/// "dd/MM/yyyy HH:mm" from ISO string in active tenant timezone.
String fmtDateSlash(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _slashFull).text;
  } catch (_) {
    return iso;
  }
}

/// "dd MMM · HH:mm:ss" from ISO string in active tenant timezone.
String fmtDateTimeSeconds(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _ddMmmHms).text;
  } catch (_) {
    return iso;
  }
}

/// "dd/MM/yyyy" from ISO string in active tenant timezone.
String fmtDateOnly(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _slashDate).text;
  } catch (_) {
    return iso;
  }
}

/// "dd/MM HH:mm" from ISO string in active tenant timezone.
String fmtDateTimeCompact(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso);
    return formatInTimeZone(dt, _slashCompact).text;
  } catch (_) {
    return iso;
  }
}

/// Full Spanish long date in active tenant timezone.
String fmtDateLongEs(DateTime d) {
  final r = toZone(d);
  final text = _heroFmt.format(r.dt);
  return r.utcFallback ? '$text (UTC)' : text;
}

/// "d MMM yyyy · HH:mm" in active tenant timezone.
String fmtDateIntl(DateTime dt) {
  final r = toZone(dt);
  final local = r.dt;
  final text = '${_dMmm.format(local)} ${local.year} \u00b7 ${_hhmm.format(local)}';
  return r.utcFallback ? '$text (UTC)' : text;
}

/// "Hoy HH:mm" / "Ayer HH:mm" / "dd/MM · HH:mm" from ISO string.
/// Both the parsed date and "now" are in active tenant timezone.
String fmtExecutionDate(String? iso) {
  if (iso == null) return '';
  try {
    final dt = DateTime.parse(iso);
    final timeR = formatInTimeZone(dt, _hhmm);
    final tzR = toZone(dt);
    final nowR = nowInZone();
    final today = DateTime(nowR.now.year, nowR.now.month, nowR.now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(tzR.dt.year, tzR.dt.month, tzR.dt.day);
    final suffix = timeR.utcFallback ? ' (UTC)' : '';
    if (day == today) return 'Hoy ${timeR.text}$suffix';
    if (day == yesterday) return 'Ayer ${timeR.text}$suffix';
    final compactR = formatInTimeZone(dt, _ddMm);
    return '${compactR.text} \u00b7 ${timeR.text}$suffix';
  } catch (_) {
    return iso;
  }
}

// ── Predicate ───────────────────────────────────────────────────────────────

/// True if [iso] parses to today in active tenant timezone.
bool isToday(String? iso) {
  if (iso == null) return false;
  try {
    final dt = DateTime.parse(iso);
    final tzR = toZone(dt);
    final nowR = nowInZone();
    return tzR.dt.year == nowR.now.year &&
        tzR.dt.month == nowR.now.month &&
        tzR.dt.day == nowR.now.day;
  } catch (_) {
    return false;
  }
}
