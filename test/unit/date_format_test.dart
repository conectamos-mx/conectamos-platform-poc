import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/date_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
  });

  // ── fmtTime ─────────────────────────────────────────────────────────────────

  group('fmtTime', () {
    test('null returns default fallback', () {
      expect(fmtTime(null), '\u2014');
    });

    test('null returns custom fallback', () {
      expect(fmtTime(null, fallback: ''), '');
    });

    test('invalid string returns fallback', () {
      expect(fmtTime('not-a-date'), '\u2014');
    });

    test('valid UTC ISO returns HH:mm in local', () {
      // Use a fixed local DateTime to avoid TZ-dependent assertions:
      // We verify the format pattern, not the exact hour.
      final result = fmtTime('2026-01-15T12:00:00Z');
      expect(result, matches(RegExp(r'^\d{2}:\d{2}$')));
    });
  });

  // ── fmtDateShort ────────────────────────────────────────────────────────────

  group('fmtDateShort', () {
    test('null returns dash', () {
      expect(fmtDateShort(null), '\u2014');
    });

    test('empty returns dash', () {
      expect(fmtDateShort(''), '\u2014');
    });

    test('invalid returns raw string', () {
      expect(fmtDateShort('bad'), 'bad');
    });

    test('valid ISO returns dd MMM · HH:mm pattern', () {
      final result = fmtDateShort('2026-03-10T08:30:00Z');
      expect(result, matches(RegExp(r'^\d{2} \w+ · \d{2}:\d{2}$')));
    });
  });

  // ── fmtDateSlash ────────────────────────────────────────────────────────────

  group('fmtDateSlash', () {
    test('null returns dash', () {
      expect(fmtDateSlash(null), '\u2014');
    });

    test('invalid returns raw', () {
      expect(fmtDateSlash('nope'), 'nope');
    });

    test('valid ISO returns dd/MM/yyyy HH:mm pattern', () {
      final result = fmtDateSlash('2026-06-15T14:30:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$')));
    });
  });

  // ── fmtDateTimeSeconds ──────────────────────────────────────────────────────

  group('fmtDateTimeSeconds', () {
    test('null returns dash', () {
      expect(fmtDateTimeSeconds(null), '\u2014');
    });

    test('valid ISO returns dd MMM · HH:mm:ss pattern', () {
      final result = fmtDateTimeSeconds('2026-01-05T09:07:03Z');
      expect(result, matches(RegExp(r'^\d{2} \w+ · \d{2}:\d{2}:\d{2}$')));
    });
  });

  // ── fmtDateOnly ─────────────────────────────────────────────────────────────

  group('fmtDateOnly', () {
    test('null returns dash', () {
      expect(fmtDateOnly(null), '\u2014');
    });

    test('valid ISO returns dd/MM/yyyy', () {
      final result = fmtDateOnly('2026-12-25T23:45:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    });
  });

  // ── fmtDateTimeCompact ──────────────────────────────────────────────────────

  group('fmtDateTimeCompact', () {
    test('null returns dash', () {
      expect(fmtDateTimeCompact(null), '\u2014');
    });

    test('valid ISO returns dd/MM HH:mm', () {
      final result = fmtDateTimeCompact('2026-08-01T06:00:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2} \d{2}:\d{2}$')));
    });
  });

  // ── fmtDateLongEs ───────────────────────────────────────────────────────────

  group('fmtDateLongEs', () {
    test('formats Monday January 5 2026 correctly', () {
      final dt = DateTime(2026, 1, 5, 10, 0);
      expect(fmtDateLongEs(dt), 'lunes, 5 de enero de 2026');
    });

    test('formats Friday December 25 2026 correctly', () {
      final dt = DateTime(2026, 12, 25, 17, 0);
      expect(fmtDateLongEs(dt), 'viernes, 25 de diciembre de 2026');
    });

    test('formats Saturday June 6 2026 correctly', () {
      final dt = DateTime(2026, 6, 6, 12, 0);
      expect(fmtDateLongEs(dt), 'sábado, 6 de junio de 2026');
    });
  });

  // ── fmtDateIntl ─────────────────────────────────────────────────────────────

  group('fmtDateIntl', () {
    test('returns d MMM yyyy · HH:mm pattern', () {
      final dt = DateTime(2026, 3, 15, 14, 30);
      final result = fmtDateIntl(dt);
      // DateTime(2026,3,15,14,30) is local — .toLocal() is a no-op.
      expect(result, contains('2026'));
      expect(result, contains('\u00b7')); // middle dot
      expect(result, matches(RegExp(r'\d{2}:\d{2}$')));
    });
  });

  // ── fmtExecutionDate ────────────────────────────────────────────────────────

  group('fmtExecutionDate', () {
    test('null returns empty string', () {
      expect(fmtExecutionDate(null), '');
    });

    test('invalid returns raw', () {
      expect(fmtExecutionDate('xyz'), 'xyz');
    });

    test('today ISO starts with Hoy', () {
      final now = DateTime.now();
      final iso = now.toUtc().toIso8601String();
      expect(fmtExecutionDate(iso), startsWith('Hoy'));
    });

    test('yesterday ISO starts with Ayer', () {
      final yesterday = DateTime.now().subtract(const Duration(hours: 25));
      final iso = yesterday.toUtc().toIso8601String();
      expect(fmtExecutionDate(iso), startsWith('Ayer'));
    });

    test('old date returns dd/MM · HH:mm pattern', () {
      final result = fmtExecutionDate('2020-01-01T12:00:00Z');
      expect(result, matches(RegExp(r'^\d{2}/\d{2} · \d{2}:\d{2}$')));
    });
  });

  // ── isToday ─────────────────────────────────────────────────────────────────

  group('isToday', () {
    test('null returns false', () {
      expect(isToday(null), false);
    });

    test('invalid returns false', () {
      expect(isToday('garbage'), false);
    });

    test('now returns true', () {
      final iso = DateTime.now().toUtc().toIso8601String();
      expect(isToday(iso), true);
    });

    test('yesterday returns false', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 2));
      final iso = yesterday.toUtc().toIso8601String();
      expect(isToday(iso), false);
    });
  });
}
