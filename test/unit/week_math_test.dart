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
      final result = mondayOf(DateTime(2026, 1, 5));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Wednesday returns Monday of same week', () {
      final result = mondayOf(DateTime(2026, 1, 7));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Sunday returns Monday of same week', () {
      final result = mondayOf(DateTime(2026, 1, 11));
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('cross-month boundary', () {
      final result = mondayOf(DateTime(2026, 1, 3));
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
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('double-digit month and day', () {
      expect(isoDate(DateTime(2026, 12, 25)), '2026-12-25');
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
      final result = weekRangeLabel(DateTime(2026, 6, 1));
      expect(result, contains('1'));
      expect(result, contains('7'));
      expect(result, contains('2026'));
      expect(result, contains('jun'));
    });

    test('cross-month range', () {
      final result = weekRangeLabel(DateTime(2025, 12, 29));
      expect(result, contains('29'));
      expect(result, contains('dic'));
      expect(result, contains('ene'));
      expect(result, contains('2025'));
    });

    test('months are lowercase (intl convention)', () {
      final result = weekRangeLabel(DateTime(2026, 1, 5));
      expect(result, contains('ene'));
      expect(result.contains('Ene'), false);
    });

    test('invalid zone does not throw', () {
      setActiveZone('Invalid/Zone');
      expect(weekRangeLabel(DateTime.utc(2026, 1, 5)), isNotEmpty);
    });
  });
}
