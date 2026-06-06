// ADR-414 — Canonical timezone-aware formatting.
// Single point of TZ conversion in the FE. All date utils delegate here.
// Fallback on invalid IANA zone: format in UTC + visible "(UTC)" marker.

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
({DateTime now, bool utcFallback}) nowInZone() {
  if (_activeLocation == null) {
    return (now: DateTime.now().toUtc(), utcFallback: true);
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
