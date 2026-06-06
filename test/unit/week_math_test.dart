import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/week_math.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
  });

  // ── mondayOf ────────────────────────────────────────────────────────────────

  group('mondayOf', () {
    test('Monday returns same day', () {
      final mon = DateTime(2026, 1, 5); // Monday
      final result = mondayOf(mon);
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Wednesday returns Monday of same week', () {
      final wed = DateTime(2026, 1, 7); // Wednesday
      final result = mondayOf(wed);
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('Sunday returns Monday of same week', () {
      final sun = DateTime(2026, 1, 11); // Sunday
      final result = mondayOf(sun);
      expect(result.weekday, DateTime.monday);
      expect(result.day, 5);
    });

    test('cross-month boundary', () {
      // Saturday Jan 3 2026 → Monday Dec 29 2025
      final sat = DateTime(2026, 1, 3);
      final result = mondayOf(sat);
      expect(result.weekday, DateTime.monday);
      expect(result.month, 12);
      expect(result.day, 29);
      expect(result.year, 2025);
    });
  });

  // ── isoDate ─────────────────────────────────────────────────────────────────

  group('isoDate', () {
    test('pads month and day', () {
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('double-digit month and day', () {
      expect(isoDate(DateTime(2026, 12, 25)), '2026-12-25');
    });
  });

  // ── weekRangeLabel ──────────────────────────────────────────────────────────

  group('weekRangeLabel', () {
    test('same-month range', () {
      final mon = DateTime(2026, 6, 1); // Monday Jun 1
      final result = weekRangeLabel(mon);
      // "1–7 jun 2026" (lowercase, intl es_MX)
      expect(result, contains('1'));
      expect(result, contains('7'));
      expect(result, contains('2026'));
      expect(result, contains('jun'));
    });

    test('cross-month range', () {
      final mon = DateTime(2025, 12, 29); // Monday Dec 29
      final result = weekRangeLabel(mon);
      expect(result, contains('29'));
      expect(result, contains('dic'));
      expect(result, contains('ene'));
      expect(result, contains('2025'));
    });

    test('months are lowercase (intl convention)', () {
      final mon = DateTime(2026, 1, 5);
      final result = weekRangeLabel(mon);
      expect(result, contains('ene'));
      // Ensure it's NOT title-case
      expect(result.contains('Ene'), false);
    });
  });
}
