import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/week_math.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
    initTz();
  });

  // ── mondayOf ────────────────────────────────────────────────────────────────

  group('mondayOf', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('Monday returns same day', () {
      // 2026-01-05 noon UTC → Jan 5 06:00 CDMX (Monday)
      final result = mondayOf(DateTime.utc(2026, 1, 5, 12));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Wednesday returns Monday of same week', () {
      // 2026-01-07 noon UTC → Jan 7 06:00 CDMX (Wednesday) → Monday = Jan 5
      final result = mondayOf(DateTime.utc(2026, 1, 7, 12));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Sunday returns Monday of same week', () {
      // 2026-01-11 noon UTC → Jan 11 06:00 CDMX (Sunday) → Monday = Jan 5
      final result = mondayOf(DateTime.utc(2026, 1, 11, 12));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('cross-month boundary', () {
      // 2026-01-03 noon UTC → Jan 3 06:00 CDMX (Saturday) → Monday = Dec 29, 2025
      final result = mondayOf(DateTime.utc(2026, 1, 3, 12));
      expect(result.weekday, DateTime.monday);
      expect(result.month, 12);
      expect(result.day, 29);
      expect(result.year, 2025);
    });

    test('invalid zone falls back to UTC', () {
      setActiveZone('Invalid/Zone');
      final result = mondayOf(DateTime.utc(2026, 1, 7, 12, 0));
      expect(result.weekday, DateTime.monday);
    });
  });

  // ── isoDate ─────────────────────────────────────────────────────────────────

  group('isoDate', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('pads month and day', () {
      // 2026-01-05 noon UTC → Jan 5 06:00 CDMX → '2026-01-05'
      expect(isoDate(DateTime.utc(2026, 1, 5, 12)), '2026-01-05');
    });

    test('double-digit month and day', () {
      // 2026-12-25 noon UTC → Dec 25 06:00 CDMX → '2026-12-25'
      expect(isoDate(DateTime.utc(2026, 12, 25, 12)), '2026-12-25');
    });

    test('invalid zone falls back to UTC', () {
      setActiveZone('Invalid/Zone');
      expect(isoDate(DateTime.utc(2026, 6, 15)), '2026-06-15');
    });
  });

  // ── weekRangeLabel ──────────────────────────────────────────────────────────

  group('weekRangeLabel', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('same-month range', () {
      // 2026-06-01 noon UTC → Jun 1 07:00 CDT (Monday). Sun = Jun 7. Same month.
      final result = weekRangeLabel(DateTime.utc(2026, 6, 1, 12));
      expect(result, contains('1'));
      expect(result, contains('7'));
      expect(result, contains('2026'));
      expect(result, contains('jun'));
    });

    test('cross-month range', () {
      // 2025-12-29 noon UTC → Dec 29 06:00 CST (Monday). Sun = Jan 4, 2026.
      final result = weekRangeLabel(DateTime.utc(2025, 12, 29, 12));
      expect(result, contains('29'));
      expect(result, contains('dic'));
      expect(result, contains('ene'));
      expect(result, contains('2025'));
    });

    test('months are lowercase (intl convention)', () {
      // 2026-01-05 noon UTC → Jan 5 06:00 CDMX (Monday)
      final result = weekRangeLabel(DateTime.utc(2026, 1, 5, 12));
      expect(result, contains('ene'));
      expect(result.contains('Ene'), false);
    });

    test('invalid zone does not throw', () {
      setActiveZone('Invalid/Zone');
      expect(weekRangeLabel(DateTime.utc(2026, 1, 5)), isNotEmpty);
    });
  });
}
