import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:conectamos_platform/core/utils/date_format.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
    initTz();
  });

  // ── fmtWeekdayEs ──────────────────────────────────────────────────────────

  group('fmtWeekdayEs', () {
    test('Monday → Lunes', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 5, 12)), 'Lunes');
    });

    test('Tuesday → Martes', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 6, 12)), 'Martes');
    });

    test('Wednesday → Miércoles', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 7, 12)), 'Miércoles');
    });

    test('Thursday → Jueves', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 8, 12)), 'Jueves');
    });

    test('Friday → Viernes', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 9, 12)), 'Viernes');
    });

    test('Saturday → Sábado', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 10, 12)), 'Sábado');
    });

    test('Sunday → Domingo', () {
      expect(fmtWeekdayEs(DateTime.utc(2026, 1, 11, 12)), 'Domingo');
    });

    test('first letter is uppercase', () {
      final result = fmtWeekdayEs(DateTime.utc(2026, 1, 5, 12));
      expect(result[0], result[0].toUpperCase());
    });
  });

  // ── fmtTime ─────────────────────────────────────────────────────────────────

  group('fmtTime', () {
    test('null returns default fallback', () {
      expect(fmtTime(null), '—');
    });

    test('null returns custom fallback', () {
      expect(fmtTime(null, fallback: ''), '');
    });

    test('invalid string returns fallback', () {
      expect(fmtTime('not-a-date'), '—');
    });

    test('valid UTC ISO returns HH:mm in tenant zone', () {
      setActiveZone('America/Mexico_City');
      // 2026-01-15T18:00:00Z → 12:00 in America/Mexico_City (CST, UTC-6)
      expect(fmtTime('2026-01-15T18:00:00Z'), '12:00');
    });

    test('invalid zone returns HH:mm (UTC) fallback', () {
      setActiveZone('Invalid/Zone');
      expect(fmtTime('2026-01-15T18:00:00Z'), '18:00 (UTC)');
    });
  });

  // ── fmtDateShort ────────────────────────────────────────────────────────────

  group('fmtDateShort', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns dash', () {
      expect(fmtDateShort(null), '—');
    });

    test('empty returns dash', () {
      expect(fmtDateShort(''), '—');
    });

    test('invalid returns raw string', () {
      expect(fmtDateShort('bad'), 'bad');
    });

    test('valid ISO returns dd MMM · HH:mm in tenant zone', () {
      final result = fmtDateShort('2026-03-10T14:30:00Z');
      expect(result, contains('08:30'));
      expect(result, matches(RegExp(r'^\d{2} \w+ · \d{2}:\d{2}$')));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final result = fmtDateShort('2026-03-10T14:30:00Z');
      expect(result, contains('(UTC)'));
      expect(result, contains('14:30'));
    });
  });

  // ── fmtDateSlash ────────────────────────────────────────────────────────────

  group('fmtDateSlash', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns dash', () {
      expect(fmtDateSlash(null), '—');
    });

    test('invalid returns raw', () {
      expect(fmtDateSlash('nope'), 'nope');
    });

    test('valid ISO returns dd/MM/yyyy HH:mm in tenant zone', () {
      final result = fmtDateSlash('2026-06-15T20:30:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$')));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final result = fmtDateSlash('2026-06-15T20:30:00Z');
      expect(result, contains('(UTC)'));
    });
  });

  // ── fmtDateTimeSeconds ──────────────────────────────────────────────────────

  group('fmtDateTimeSeconds', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns dash', () {
      expect(fmtDateTimeSeconds(null), '—');
    });

    test('valid ISO returns dd MMM · HH:mm:ss in tenant zone', () {
      // UTC 15:07:03 → Mexico City 09:07:03 (CST)
      expect(fmtDateTimeSeconds('2026-01-05T15:07:03Z'), contains('09:07:03'));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final result = fmtDateTimeSeconds('2026-01-05T15:07:03Z');
      expect(result, contains('(UTC)'));
      expect(result, contains('15:07:03'));
    });
  });

  // ── fmtDateOnly ─────────────────────────────────────────────────────────────

  group('fmtDateOnly', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns dash', () {
      expect(fmtDateOnly(null), '—');
    });

    test('valid ISO returns dd/MM/yyyy in tenant zone', () {
      // UTC 04:00 Jan 1 → Dec 31 22:00 in Mexico City (UTC-6)
      expect(fmtDateOnly('2026-01-01T04:00:00Z'), '31/12/2025');
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final result = fmtDateOnly('2026-01-01T04:00:00Z');
      expect(result, contains('(UTC)'));
      expect(result, contains('01/01/2026'));
    });
  });

  // ── fmtDateTimeCompact ──────────────────────────────────────────────────────

  group('fmtDateTimeCompact', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns dash', () {
      expect(fmtDateTimeCompact(null), '—');
    });

    test('valid ISO returns dd/MM HH:mm in tenant zone', () {
      final result = fmtDateTimeCompact('2026-08-01T12:00:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2} \d{2}:\d{2}$')));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      expect(fmtDateTimeCompact('2026-08-01T12:00:00Z'), contains('(UTC)'));
    });
  });

  // ── fmtDateLongEs ───────────────────────────────────────────────────────────

  group('fmtDateLongEs', () {
    test('formats in tenant zone', () {
      setActiveZone('America/Mexico_City');
      // UTC midnight+4 Jan 1 → Dec 31 in Mexico City
      final dt = DateTime.utc(2026, 1, 1, 4, 0);
      final result = fmtDateLongEs(dt);
      expect(result, contains('miércoles'));
      expect(result, contains('31'));
      expect(result, contains('diciembre'));
      expect(result, contains('2025'));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final dt = DateTime.utc(2026, 1, 5, 10, 0);
      final result = fmtDateLongEs(dt);
      expect(result, contains('(UTC)'));
      expect(result, contains('lunes'));
    });
  });

  // ── fmtDateIntl ─────────────────────────────────────────────────────────────

  group('fmtDateIntl', () {
    test('returns d MMM yyyy · HH:mm in tenant zone', () {
      setActiveZone('America/Mexico_City');
      final dt = DateTime.utc(2026, 3, 15, 20, 30);
      final result = fmtDateIntl(dt);
      expect(result, contains('2026'));
      expect(result, contains('·'));
      expect(result, contains('14:30'));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final dt = DateTime.utc(2026, 3, 15, 20, 30);
      final result = fmtDateIntl(dt);
      expect(result, contains('(UTC)'));
      expect(result, contains('20:30'));
    });
  });

  // ── fmtExecutionDate ────────────────────────────────────────────────────────

  group('fmtExecutionDate', () {
    setUp(() => setActiveZone('America/Mexico_City'));
    tearDown(() => setNowForTest(null));

    test('null returns empty string', () {
      expect(fmtExecutionDate(null), '');
    });

    test('invalid returns raw', () {
      expect(fmtExecutionDate('xyz'), 'xyz');
    });

    test('today ISO starts with Hoy', () {
      // Fix now to 2026-06-10 18:00 UTC = 12:00 CDMX
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      expect(fmtExecutionDate(now.toIso8601String()), startsWith('Hoy'));
    });

    test('yesterday ISO starts with Ayer', () {
      // Fix now to 2026-06-10 18:00 UTC = 12:00 CDMX
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final loc = tz.getLocation('America/Mexico_City');
      final yesterdayNoon = tz.TZDateTime(loc, 2026, 6, 9, 12, 0);
      expect(fmtExecutionDate(yesterdayNoon.toUtc().toIso8601String()), startsWith('Ayer'));
    });

    test('old date returns dd/MM · HH:mm pattern', () {
      expect(fmtExecutionDate('2020-01-01T12:00:00Z'),
          matches(RegExp(r'^\d{2}/\d{2} · \d{2}:\d{2}$')));
    });

    test('invalid zone includes (UTC) marker', () {
      setActiveZone('Invalid/Zone');
      expect(fmtExecutionDate('2020-01-01T12:00:00Z'), contains('(UTC)'));
    });

    test('regression: yesterday at 00:30 tenant (deploy #205 failure window)', () {
      // 06:30 UTC = 00:30 CDMX — the exact window that caused flaky failure
      final now = DateTime.utc(2026, 6, 10, 6, 30);
      setNowForTest(now);
      final loc = tz.getLocation('America/Mexico_City');
      final yesterdayNoon = tz.TZDateTime(loc, 2026, 6, 9, 12, 0);
      expect(fmtExecutionDate(yesterdayNoon.toUtc().toIso8601String()), startsWith('Ayer'));
      expect(fmtDateGroupLabel(yesterdayNoon.toUtc()), 'Ayer');
      final r = fmtCreatedCell(yesterdayNoon.toUtc().toIso8601String());
      expect(r.dateLine, startsWith('Ayer, '));
    });
  });

  // ── isToday ─────────────────────────────────────────────────────────────────

  group('isToday', () {
    setUp(() => setActiveZone('America/Mexico_City'));
    tearDown(() => setNowForTest(null));

    test('null returns false', () {
      expect(isToday(null), false);
    });

    test('invalid returns false', () {
      expect(isToday('garbage'), false);
    });

    test('now returns true', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      expect(isToday(now.toIso8601String()), true);
    });

    test('2 days ago returns false', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final old = DateTime.utc(2026, 6, 8, 18, 0);
      expect(isToday(old.toIso8601String()), false);
    });
  });

  // ── fmtDateGroupLabel ──────────────────────────────────────────────────────

  group('fmtDateGroupLabel', () {
    setUp(() => setActiveZone('America/Mexico_City'));
    tearDown(() => setNowForTest(null));

    test('today returns Hoy', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      expect(fmtDateGroupLabel(now), 'Hoy');
    });

    test('yesterday returns Ayer', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final loc = tz.getLocation('America/Mexico_City');
      final yesterdayNoon = tz.TZDateTime(loc, 2026, 6, 9, 12, 0);
      expect(fmtDateGroupLabel(yesterdayNoon.toUtc()), 'Ayer');
    });

    test('old date returns d mmm yyyy via intl', () {
      final dt = DateTime.utc(2026, 3, 15, 12, 0);
      final result = fmtDateGroupLabel(dt);
      // intl es_MX: "15 mar 2026" (lowercase)
      expect(result, contains('15'));
      expect(result, contains('mar'));
      expect(result, contains('2026'));
    });

    test('uses tenant timezone not browser timezone', () {
      // 2026-01-01T04:00:00Z → Dec 31 22:00 in Mexico City (UTC-6)
      // If using browser TZ this could be Jan 1 — but in CDMX it's Dec 31
      setActiveZone('America/Mexico_City');
      final dt = DateTime.utc(2026, 1, 1, 4, 0);
      final result = fmtDateGroupLabel(dt);
      expect(result, contains('31'));
      expect(result, contains('dic'));
      expect(result, contains('2025'));
    });

    test('invalid zone returns date with (UTC) suffix', () {
      setActiveZone('Invalid/Zone');
      final dt = DateTime.utc(2026, 6, 15, 12, 0);
      final result = fmtDateGroupLabel(dt);
      expect(result, contains('(UTC)'));
    });

    test('invalid zone today returns Hoy (UTC)', () {
      setActiveZone('Invalid/Zone');
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      expect(fmtDateGroupLabel(now), 'Hoy (UTC)');
    });
  });

  // ── fmtCreatedCell ─────────────────────────────────────────────────────────

  group('fmtCreatedCell', () {
    setUp(() => setActiveZone('America/Mexico_City'));
    tearDown(() => setNowForTest(null));

    test('null returns dash dateLine and empty relativeLine', () {
      final r = fmtCreatedCell(null);
      expect(r.dateLine, '—');
      expect(r.relativeLine, '');
    });

    test('today returns Hoy, HH:mm + Ahora', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final r = fmtCreatedCell(now.toIso8601String());
      expect(r.dateLine, startsWith('Hoy, '));
      expect(r.dateLine, matches(RegExp(r'^Hoy, \d{2}:\d{2}$')));
      expect(r.relativeLine, 'Ahora');
    });

    test('yesterday returns Ayer, HH:mm', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final loc = tz.getLocation('America/Mexico_City');
      final yesterdayNoon = tz.TZDateTime(loc, 2026, 6, 9, 12, 0);
      final r = fmtCreatedCell(yesterdayNoon.toUtc().toIso8601String());
      expect(r.dateLine, startsWith('Ayer, '));
    });

    test('old date returns d mmm, HH:mm with comma', () {
      final r = fmtCreatedCell('2026-01-15T18:00:00Z');
      // Mexico City: 12:00
      expect(r.dateLine, contains(','));
      expect(r.dateLine, contains('12:00'));
    });

    test('uses tenant timezone not browser timezone', () {
      // 2026-01-01T04:00:00Z → Dec 31 22:00 in Mexico City
      final r = fmtCreatedCell('2026-01-01T04:00:00Z');
      expect(r.dateLine, contains('31'));
      expect(r.dateLine, contains('22:00'));
    });

    test('invalid zone appends (UTC)', () {
      setActiveZone('Invalid/Zone');
      final r = fmtCreatedCell('2026-06-15T12:00:00Z');
      expect(r.dateLine, contains('(UTC)'));
    });

    test('relativeLine delegates to fmtRelative', () {
      final now = DateTime.utc(2026, 6, 10, 18, 0);
      setNowForTest(now);
      final dt = now.subtract(const Duration(minutes: 5));
      final r = fmtCreatedCell(dt.toIso8601String());
      expect(r.relativeLine, 'Hace 5 min');
    });
  });

  // ── Initial state (before setActiveZone) ──────────────────────────────────

  group('initial UTC state', () {
    test('before setActiveZone, format uses UTC with (UTC) marker', () {
      setActiveZone(''); // force invalid → UTC fallback
      final result = fmtTime('2026-01-15T18:00:00Z');
      expect(result, '18:00 (UTC)');
    });
  });
}
