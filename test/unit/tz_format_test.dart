import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

void main() {
  setUpAll(() {
    initTz();
  });

  // ── startOfDay ──────────────────────────────────────────────────────────────

  group('startOfDay', () {
    test('returns 00:00:00.000 in tenant zone (America/Mexico_City)', () {
      setActiveZone('America/Mexico_City');
      // 2026-01-15T08:30:00Z → 02:30 CDMX (CST, UTC-6)
      final result = startOfDay(DateTime.utc(2026, 1, 15, 8, 30));
      expect(result.utcFallback, false);
      expect(result.dt.hour, 0);
      expect(result.dt.minute, 0);
      expect(result.dt.second, 0);
      expect(result.dt.millisecond, 0);
      expect(result.dt.day, 15);
      expect(result.dt.month, 1);
    });

    test('cross-midnight: UTC day differs from tenant day', () {
      setActiveZone('America/Mexico_City');
      // 2026-01-16T04:00:00Z → 2026-01-15 22:00 CDMX
      final result = startOfDay(DateTime.utc(2026, 1, 16, 4, 0));
      expect(result.dt.day, 15);
      expect(result.dt.hour, 0);
    });

    test('DST transition day (America/New_York spring forward)', () {
      setActiveZone('America/New_York');
      // 2026-03-08 is DST spring-forward in US (clocks jump 2:00→3:00)
      final result = startOfDay(DateTime.utc(2026, 3, 8, 12, 0));
      expect(result.utcFallback, false);
      expect(result.dt.day, 8);
      expect(result.dt.hour, 0);
      expect(result.dt.minute, 0);
    });

    test('DST transition day (America/New_York fall back)', () {
      setActiveZone('America/New_York');
      // 2026-11-01 is DST fall-back in US (clocks repeat 1:00–2:00)
      final result = startOfDay(DateTime.utc(2026, 11, 1, 12, 0));
      expect(result.utcFallback, false);
      expect(result.dt.day, 1);
      expect(result.dt.hour, 0);
      expect(result.dt.minute, 0);
    });

    test('UTC fallback when no active zone', () {
      setActiveZone('');
      final result = startOfDay(DateTime.utc(2026, 1, 15, 8, 30));
      expect(result.utcFallback, true);
      expect(result.dt.hour, 0);
      expect(result.dt.day, 15);
    });
  });

  // ── endOfDay ────────────────────────────────────────────────────────────────

  group('endOfDay', () {
    test('returns 23:59:59.999 in tenant zone (America/Mexico_City)', () {
      setActiveZone('America/Mexico_City');
      final result = endOfDay(DateTime.utc(2026, 1, 15, 8, 30));
      expect(result.utcFallback, false);
      expect(result.dt.hour, 23);
      expect(result.dt.minute, 59);
      expect(result.dt.second, 59);
      expect(result.dt.millisecond, 999);
      expect(result.dt.day, 15);
    });

    test('cross-midnight: UTC day differs from tenant day', () {
      setActiveZone('America/Mexico_City');
      // 2026-01-16T04:00:00Z → 2026-01-15 22:00 CDMX → endOfDay = Jan 15 23:59:59.999
      final result = endOfDay(DateTime.utc(2026, 1, 16, 4, 0));
      expect(result.dt.day, 15);
      expect(result.dt.hour, 23);
      expect(result.dt.minute, 59);
      expect(result.dt.second, 59);
    });

    test('DST transition day (America/New_York spring forward)', () {
      setActiveZone('America/New_York');
      final result = endOfDay(DateTime.utc(2026, 3, 8, 12, 0));
      expect(result.utcFallback, false);
      expect(result.dt.day, 8);
      expect(result.dt.hour, 23);
      expect(result.dt.minute, 59);
      expect(result.dt.second, 59);
      expect(result.dt.millisecond, 999);
    });

    test('DST transition day (America/New_York fall back)', () {
      setActiveZone('America/New_York');
      final result = endOfDay(DateTime.utc(2026, 11, 1, 12, 0));
      expect(result.utcFallback, false);
      expect(result.dt.day, 1);
      expect(result.dt.hour, 23);
      expect(result.dt.minute, 59);
    });

    test('UTC fallback when no active zone', () {
      setActiveZone('');
      final result = endOfDay(DateTime.utc(2026, 1, 15, 8, 30));
      expect(result.utcFallback, true);
      expect(result.dt.hour, 23);
      expect(result.dt.minute, 59);
      expect(result.dt.second, 59);
      expect(result.dt.millisecond, 999);
      expect(result.dt.day, 15);
    });
  });
}
