// ADR-414 — Canonical timezone-aware formatting.
// Single point of TZ conversion in the FE. All date utils delegate here.
// Fallback on invalid IANA zone: format in UTC + visible "(UTC)" marker.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ── Init (call once from main) ───────────────────────────────────────────────

bool _initialized = false;

void initTz() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

// ── Active zone global (mirror of activeTenantZoneProvider) ─────────────────

tz.Location? _activeLocation;

/// Set the active tenant timezone. Called by the Riverpod sync provider
/// whenever the active tenant changes.
///
/// If [iana] is invalid or empty → stays in UTC fallback mode.
/// The provider is the source of truth; this global is a read-only mirror
/// for contexts without WidgetRef (static helpers, callbacks, exports).
void setActiveZone(String iana) {
  try {
    _activeLocation = tz.getLocation(iana);
  } catch (_) {
    _activeLocation = null;
  }
}

// ── Test-only now override ───────────────────────────────────────────────────

DateTime? _nowOverrideUtc;

/// Override the "now" instant used by [nowInZone] for deterministic tests.
///
/// [nowUtc] must be a UTC instant (or null to restore real clock).
/// Use in tests that assert calendar-day semantics (Hoy/Ayer/group labels).
/// Always call `setNowForTest(null)` in tearDown to avoid leaking state.
@visibleForTesting
void setNowForTest(DateTime? nowUtc) {
  _nowOverrideUtc = nowUtc;
}

// ── Canonical conversion ─────────────────────────────────────────────────────

/// Format [utcInstant] in the active tenant timezone using [fmt].
/// Returns formatted text + whether UTC fallback was used.
/// Fallback is NEVER silent — the string carries "(UTC)" when zone is invalid.
({String text, bool utcFallback}) formatInTimeZone(
  DateTime utcInstant,
  DateFormat fmt,
) {
  if (_activeLocation == null) {
    final utcDt = utcInstant.toUtc();
    return (text: '${fmt.format(utcDt)} (UTC)', utcFallback: true);
  }
  final tzDt = tz.TZDateTime.from(utcInstant, _activeLocation!);
  return (text: fmt.format(tzDt), utcFallback: false);
}

/// DateTime.now() in active tenant timezone. Falls back to UTC.
/// If [setNowForTest] has been called with a non-null value, uses that
/// instant instead of the real clock — for deterministic calendar-day tests.
({DateTime now, bool utcFallback}) nowInZone() {
  if (_activeLocation == null) {
    return (now: _nowOverrideUtc?.toUtc() ?? DateTime.now().toUtc(), utcFallback: true);
  }
  if (_nowOverrideUtc != null) {
    return (now: tz.TZDateTime.from(_nowOverrideUtc!, _activeLocation!), utcFallback: false);
  }
  return (now: tz.TZDateTime.now(_activeLocation!), utcFallback: false);
}

/// Convert any DateTime to active tenant timezone. Falls back to UTC.
({DateTime dt, bool utcFallback}) toZone(DateTime instant) {
  if (_activeLocation == null) {
    return (dt: instant.toUtc(), utcFallback: true);
  }
  return (dt: tz.TZDateTime.from(instant, _activeLocation!), utcFallback: false);
}

/// Start of calendar day (00:00:00.000) in active tenant timezone.
/// [instant] is converted to tenant zone first to determine the calendar day.
({DateTime dt, bool utcFallback}) startOfDay(DateTime instant) {
  if (_activeLocation == null) {
    final u = instant.toUtc();
    return (dt: DateTime.utc(u.year, u.month, u.day), utcFallback: true);
  }
  final inZone = tz.TZDateTime.from(instant, _activeLocation!);
  return (
    dt: tz.TZDateTime(_activeLocation!, inZone.year, inZone.month, inZone.day),
    utcFallback: false,
  );
}

/// End of calendar day (23:59:59.999) in active tenant timezone.
/// [instant] is converted to tenant zone first to determine the calendar day.
({DateTime dt, bool utcFallback}) endOfDay(DateTime instant) {
  if (_activeLocation == null) {
    final u = instant.toUtc();
    return (
      dt: DateTime.utc(u.year, u.month, u.day, 23, 59, 59, 999),
      utcFallback: true,
    );
  }
  final inZone = tz.TZDateTime.from(instant, _activeLocation!);
  return (
    dt: tz.TZDateTime(
        _activeLocation!, inZone.year, inZone.month, inZone.day, 23, 59, 59, 999),
    utcFallback: false,
  );
}
