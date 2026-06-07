import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/tz_format.dart';

/// Standalone reproduction of _matchesDateFilter logic from
/// conversations_screen.dart, extracted for unit testing.
/// Mirrors the production code exactly — kept in sync manually.
bool matchesDateFilter({
  required Map<String, dynamic> msg,
  required DateRange? dateRange,
  required TimeOfDaySimple? fromTime,
  required TimeOfDaySimple? toTime,
}) {
  if (dateRange == null && fromTime == null) return true;
  final receivedAt =
      DateTime.tryParse(msg['received_at'] as String? ?? '');
  if (receivedAt == null) return false;
  final tzMsg = toZone(receivedAt).dt;
  if (dateRange != null) {
    final rangeStart = startOfDay(dateRange.start).dt;
    final rangeEnd = endOfDay(dateRange.end).dt;
    if (tzMsg.isBefore(rangeStart)) return false;
    if (tzMsg.isAfter(rangeEnd)) return false;
  } else if (fromTime != null || toTime != null) {
    final tzNow = nowInZone().now;
    final isTodayTz = tzMsg.year == tzNow.year &&
        tzMsg.month == tzNow.month &&
        tzMsg.day == tzNow.day;
    if (!isTodayTz) return false;
  }
  if (fromTime != null) {
    final fromMinutes = fromTime.hour * 60 + fromTime.minute;
    final msgMinutes = tzMsg.hour * 60 + tzMsg.minute;
    if (msgMinutes < fromMinutes) return false;
  }
  if (toTime != null) {
    final toMinutes = toTime.hour * 60 + toTime.minute;
    final msgMinutes = tzMsg.hour * 60 + tzMsg.minute;
    if (msgMinutes > toMinutes) return false;
  }
  return true;
}

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);
}

class TimeOfDaySimple {
  final int hour;
  final int minute;
  const TimeOfDaySimple(this.hour, this.minute);
}

void main() {
  setUpAll(() {
    initTz();
  });

  // Helper: build msg map with received_at
  Map<String, dynamic> msg(String iso) => {'received_at': iso};

  group('_matchesDateFilter (tenant-zone)', () {
    setUp(() {
      setActiveZone('America/Mexico_City'); // CST = UTC-6
    });

    test('no filters → always matches', () {
      expect(
        matchesDateFilter(
          msg: msg('2026-01-15T12:00:00Z'),
          dateRange: null,
          fromTime: null,
          toTime: null,
        ),
        true,
      );
    });

    test('msg at 23:30 tenant-time on last day of range → INCLUDED', () {
      // 2026-01-15 23:30 CDMX = 2026-01-16 05:30 UTC
      final range = DateRange(DateTime(2026, 1, 14), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-16T05:30:00Z'),
          dateRange: range,
          fromTime: null,
          toTime: null,
        ),
        true,
      );
    });

    test('msg at 00:30 tenant-time day AFTER range → EXCLUDED', () {
      // 2026-01-16 00:30 CDMX = 2026-01-16 06:30 UTC
      final range = DateRange(DateTime(2026, 1, 14), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-16T06:30:00Z'),
          dateRange: range,
          fromTime: null,
          toTime: null,
        ),
        false,
      );
    });

    test('msg before range start → EXCLUDED', () {
      // 2026-01-13 23:00 CDMX = 2026-01-14 05:00 UTC
      final range = DateRange(DateTime(2026, 1, 14), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-14T05:00:00Z'),
          dateRange: range,
          fromTime: null,
          toTime: null,
        ),
        false,
      );
    });

    test('isToday: msg at 23:30 tenant-time today → INCLUDED even if UTC next day', () {
      // Use nowInZone to determine "today" in tenant zone
      final tzNow = nowInZone().now;
      // Build a timestamp for 23:30 today in CDMX
      final todayEnd = DateTime.utc(
        tzNow.year, tzNow.month, tzNow.day, 23, 30,
      );
      // Convert that to UTC by adding 6h (CST offset)
      final asUtc = todayEnd.add(const Duration(hours: 6));
      expect(
        matchesDateFilter(
          msg: msg(asUtc.toIso8601String()),
          dateRange: null,
          fromTime: const TimeOfDaySimple(0, 0),
          toTime: null,
        ),
        true,
      );
    });

    test('time filter: msg within from-to window → INCLUDED', () {
      // 2026-01-15 14:30 CDMX = 2026-01-15 20:30 UTC
      final range = DateRange(DateTime(2026, 1, 15), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-15T20:30:00Z'),
          dateRange: range,
          fromTime: const TimeOfDaySimple(14, 0),
          toTime: const TimeOfDaySimple(15, 0),
        ),
        true,
      );
    });

    test('time filter: msg outside from-to window → EXCLUDED', () {
      // 2026-01-15 13:30 CDMX = 2026-01-15 19:30 UTC
      final range = DateRange(DateTime(2026, 1, 15), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-15T19:30:00Z'),
          dateRange: range,
          fromTime: const TimeOfDaySimple(14, 0),
          toTime: const TimeOfDaySimple(15, 0),
        ),
        false,
      );
    });

    test('null received_at → EXCLUDED', () {
      expect(
        matchesDateFilter(
          msg: <String, dynamic>{},
          dateRange: DateRange(DateTime(2026, 1, 14), DateTime(2026, 1, 15)),
          fromTime: null,
          toTime: null,
        ),
        false,
      );
    });
  });

  group('regression: tenant=CDMX, browser=CDMX', () {
    setUp(() {
      setActiveZone('America/Mexico_City');
    });

    test('msg mid-day in range → INCLUDED', () {
      // 2026-01-15 12:00 CDMX = 2026-01-15 18:00 UTC
      final range = DateRange(DateTime(2026, 1, 15), DateTime(2026, 1, 15));
      expect(
        matchesDateFilter(
          msg: msg('2026-01-15T18:00:00Z'),
          dateRange: range,
          fromTime: null,
          toTime: null,
        ),
        true,
      );
    });

    test('msg outside range → EXCLUDED', () {
      final range = DateRange(DateTime(2026, 1, 15), DateTime(2026, 1, 15));
      // 2026-01-14 12:00 CDMX = 2026-01-14 18:00 UTC
      expect(
        matchesDateFilter(
          msg: msg('2026-01-14T18:00:00Z'),
          dateRange: range,
          fromTime: null,
          toTime: null,
        ),
        false,
      );
    });
  });
}
