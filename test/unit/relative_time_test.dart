import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/relative_time.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() {
    initTz();
  });

  // ── fmtRelative ─────────────────────────────────────────────────────────────

  group('fmtRelative', () {
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

  // ── elapsedSince ────────────────────────────────────────────────────────────

  group('elapsedSince', () {
    setUp(() => setActiveZone('America/Mexico_City'));

    test('just now returns hace 0s', () {
      expect(elapsedSince(DateTime.now()), 'hace 0s');
    });

    test('30 seconds ago returns hace 30s', () {
      final t = DateTime.now().subtract(const Duration(seconds: 30));
      expect(elapsedSince(t), 'hace 30s');
    });

    test('5 minutes ago returns hace 5m', () {
      final t = DateTime.now().subtract(const Duration(minutes: 5));
      expect(elapsedSince(t), 'hace 5m');
    });

    test('2 hours ago returns hace 2h', () {
      final t = DateTime.now().subtract(const Duration(hours: 2));
      expect(elapsedSince(t), 'hace 2h');
    });

    test('works with invalid zone (fallback UTC)', () {
      setActiveZone('Invalid/Zone');
      final t = DateTime.now().subtract(const Duration(minutes: 3));
      expect(elapsedSince(t), contains('hace'));
    });
  });
}
