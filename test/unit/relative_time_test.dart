import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/relative_time.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
    initTz();
  });

  // ── fmtRelative (default / Title-case verbose) ────────────────────────────

  group('fmtRelative default', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('null returns default dash', () {
      expect(fmtRelative(null), '—');
    });

    test('null returns custom nullLabel', () {
      expect(fmtRelative(null, nullLabel: 'Nunca'), 'Nunca');
    });

    test('invalid string returns dash', () {
      expect(fmtRelative('bad'), '—');
    });

    test('just now returns Ahora (showSeconds=false)', () {
      final iso = DateTime.now().toUtc().toIso8601String();
      expect(fmtRelative(iso), 'Ahora');
    });

    test('just now returns Hace 0s (showSeconds=true)', () {
      final iso = DateTime.now().toUtc().toIso8601String();
      final result = fmtRelative(iso, showSeconds: true);
      expect(result, startsWith('Hace'));
      expect(result, endsWith('s'));
    });

    test('5 minutes ago returns Hace 5 min', () {
      final dt = DateTime.now().subtract(const Duration(minutes: 5));
      expect(fmtRelative(dt.toUtc().toIso8601String()), 'Hace 5 min');
    });

    test('3 hours ago returns Hace 3h', () {
      final dt = DateTime.now().subtract(const Duration(hours: 3));
      expect(fmtRelative(dt.toUtc().toIso8601String()), 'Hace 3h');
    });

    test('exactly 1 day ago returns Ayer', () {
      final dt = DateTime.now().subtract(const Duration(hours: 25));
      expect(fmtRelative(dt.toUtc().toIso8601String()), 'Ayer');
    });

    test('7 days ago returns Hace 7 días', () {
      final dt = DateTime.now().subtract(const Duration(days: 7));
      expect(fmtRelative(dt.toUtc().toIso8601String()), contains('7'));
    });

    test('works with invalid zone (fallback UTC)', () {
      setActiveZone('Invalid/Zone');
      final iso = DateTime.now().toUtc().toIso8601String();
      expect(fmtRelative(iso), isNotEmpty);
    });
  });

  // ── fmtRelative compact ──────────────────────────────────────────────────

  group('fmtRelative compact', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('just now returns ahora', () {
      final iso = DateTime.now().toUtc().toIso8601String();
      expect(fmtRelative(iso, compact: true), 'ahora');
    });

    test('just now with showSeconds returns hace Xs', () {
      final iso = DateTime.now().toUtc().toIso8601String();
      final result = fmtRelative(iso, compact: true, showSeconds: true);
      expect(result, startsWith('hace'));
      expect(result, endsWith('s'));
    });

    test('5 minutes ago returns hace 5m', () {
      final dt = DateTime.now().subtract(const Duration(minutes: 5));
      expect(fmtRelative(dt.toUtc().toIso8601String(), compact: true), 'hace 5m');
    });

    test('3 hours ago returns hace 3h', () {
      final dt = DateTime.now().subtract(const Duration(hours: 3));
      expect(fmtRelative(dt.toUtc().toIso8601String(), compact: true), 'hace 3h');
    });

    test('1 day ago returns ayer', () {
      final dt = DateTime.now().subtract(const Duration(hours: 25));
      expect(fmtRelative(dt.toUtc().toIso8601String(), compact: true), 'ayer');
    });

    test('3 days ago returns hace 3d', () {
      final dt = DateTime.now().subtract(const Duration(days: 3));
      expect(fmtRelative(dt.toUtc().toIso8601String(), compact: true), 'hace 3d');
    });
  });

  // ── fmtRelative absoluteAfterDays ─────────────────────────────────────────

  group('fmtRelative absoluteAfterDays', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('6 days with absoluteAfterDays=7 returns relative', () {
      final dt = DateTime.now().subtract(const Duration(days: 6));
      final result = fmtRelative(
        dt.toUtc().toIso8601String(),
        compact: true,
        absoluteAfterDays: 7,
      );
      expect(result, contains('6'));
      expect(result, isNot(contains('/')));
    });

    test('8 days with absoluteAfterDays=7 returns dd/MM/yyyy', () {
      final dt = DateTime.now().subtract(const Duration(days: 8));
      final result = fmtRelative(
        dt.toUtc().toIso8601String(),
        compact: true,
        absoluteAfterDays: 7,
      );
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });

    test('absoluteAfterDays uses tenant timezone for date', () {
      setActiveZone('America/Mexico_City');
      // 10 days ago at 4am UTC → in Mexico City it's previous day
      final dt = DateTime.now().subtract(const Duration(days: 10));
      final result = fmtRelative(
        dt.toUtc().toIso8601String(),
        absoluteAfterDays: 7,
      );
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });

    test('absoluteAfterDays with invalid zone returns absolute date', () {
      setActiveZone('Invalid/Zone');
      final dt = DateTime.now().subtract(const Duration(days: 10));
      final result = fmtRelative(
        dt.toUtc().toIso8601String(),
        absoluteAfterDays: 7,
      );
      // Falls back to UTC — still returns dd/MM/yyyy (no (UTC) suffix for absolute dates)
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });
  });

  // ── fmtElapsedSeconds ───────────────────────────────────────────────────────

  group('fmtElapsedSeconds', () {
    test('null returns dash', () {
      expect(fmtElapsedSeconds(null), '—');
    });

    test('45 seconds', () {
      expect(fmtElapsedSeconds(45), '45s');
    });

    test('90 seconds', () {
      expect(fmtElapsedSeconds(90), '1m 30s');
    });

    test('3661 seconds', () {
      expect(fmtElapsedSeconds(3661), '1h 1m');
    });

    test('0 seconds', () {
      expect(fmtElapsedSeconds(0), '0s');
    });

    test('59 seconds', () {
      expect(fmtElapsedSeconds(59), '59s');
    });

    test('60 seconds', () {
      expect(fmtElapsedSeconds(60), '1m 0s');
    });

    test('3600 seconds', () {
      expect(fmtElapsedSeconds(3600), '1h 0m');
    });
  });
}
