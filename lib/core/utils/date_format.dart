// ADR-413 — Extracted date/time formatting helpers (pure functions).
// TZ handling preserved byte-identical from each original source.
// String output standardised to DateFormat with locale es_MX.

import 'package:intl/intl.dart';

// ── Shared DateFormat instances ──────────────────────────────────────────────

final _hhmm = DateFormat('HH:mm');
final _ddMmmHm = DateFormat("dd MMM '·' HH:mm", 'es_MX');
final _ddMmmHms = DateFormat("dd MMM '·' HH:mm:ss", 'es_MX');
final _slashFull = DateFormat('dd/MM/yyyy HH:mm');
final _slashDate = DateFormat('dd/MM/yyyy');
final _slashCompact = DateFormat('dd/MM HH:mm');
final _heroFmt = DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'es_MX');
final _dMmm = DateFormat('d MMM', 'es_MX');
final _ddMm = DateFormat('dd/MM');

// ── Absolute format: ISO string → localised string ──────────────────────────

/// "HH:mm" from ISO string. Applies `.toLocal()`.
/// [fallback] returned on null or parse error (conv uses '', dash uses '—').
String fmtTime(String? iso, {String fallback = '\u2014'}) {
  if (iso == null) return fallback;
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _hhmm.format(dt);
  } catch (_) {
    return fallback;
  }
}

/// "dd MMM · HH:mm" from ISO string. Applies `.toLocal()`.
String fmtDateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '\u2014';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _ddMmmHm.format(dt);
  } catch (_) {
    return iso;
  }
}

/// "dd/MM/yyyy HH:mm" from ISO string. Applies `.toLocal()`.
String fmtDateSlash(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _slashFull.format(dt);
  } catch (_) {
    return iso;
  }
}

/// "dd MMM · HH:mm:ss" from ISO string. Applies `.toLocal()`.
String fmtDateTimeSeconds(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _ddMmmHms.format(dt);
  } catch (_) {
    return iso;
  }
}

/// "dd/MM/yyyy" from ISO string. Applies `.toLocal()`.
String fmtDateOnly(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _slashDate.format(dt);
  } catch (_) {
    return iso;
  }
}

/// "dd/MM HH:mm" from ISO string. Applies `.toLocal()`.
String fmtDateTimeCompact(String? iso) {
  if (iso == null) return '\u2014';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return _slashCompact.format(dt);
  } catch (_) {
    return iso;
  }
}

/// Full Spanish long date from DateTime. Naive — no TZ conversion.
/// Caller must pass an already-local DateTime (e.g. DateTime.now()).
String fmtDateLongEs(DateTime d) => _heroFmt.format(d);

/// "d MMM yyyy · HH:mm" from DateTime. Applies `.toLocal()`.
String fmtDateIntl(DateTime dt) {
  final local = dt.toLocal();
  return '${_dMmm.format(local)} ${local.year} · ${_hhmm.format(local)}';
}

/// "Hoy HH:mm" / "Ayer HH:mm" / "dd/MM · HH:mm" from ISO string.
/// Applies `.toLocal()`. Hybrid format+relative.
String fmtExecutionDate(String? iso) {
  if (iso == null) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);
    final time = _hhmm.format(dt);
    if (day == today) return 'Hoy $time';
    if (day == yesterday) return 'Ayer $time';
    return '${_ddMm.format(dt)} \u00b7 $time';
  } catch (_) {
    return iso;
  }
}

// ── Predicate ───────────────────────────────────────────────────────────────

/// True if [iso] parses to today in local time. Applies `.toLocal()`.
bool isToday(String? iso) {
  if (iso == null) return false;
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  } catch (_) {
    return false;
  }
}
