import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:conectamos_platform/core/utils/scope_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
    await initializeDateFormatting('es', null);
  });

  group('parseScope', () {
    test('null returns (null, null)', () {
      expect(parseScope(null), (null, null));
    });

    test('empty string returns (null, null)', () {
      expect(parseScope(''), (null, null));
    });

    test('malformed string returns (null, null)', () {
      expect(parseScope('garbage'), (null, null));
    });

    test('single value (no comma) returns (null, null)', () {
      expect(parseScope('[2025-01-01T00:00:00Z]'), (null, null));
    });

    test('valid range "[lo,hi)" parses correctly', () {
      final (lo, hi) = parseScope(
          '["2025-06-01T09:00:00Z","2025-06-01T17:00:00Z")');
      expect(lo, isNotNull);
      expect(hi, isNotNull);
      expect(lo!.toUtc(), DateTime.utc(2025, 6, 1, 9));
      expect(hi!.toUtc(), DateTime.utc(2025, 6, 1, 17));
    });

    test('range without quotes parses correctly', () {
      final (lo, hi) =
          parseScope('[2025-06-01T09:00:00Z,2025-06-01T17:00:00Z)');
      expect(lo, isNotNull);
      expect(hi, isNotNull);
      expect(lo!.toUtc(), DateTime.utc(2025, 6, 1, 9));
      expect(hi!.toUtc(), DateTime.utc(2025, 6, 1, 17));
    });

    test('input without Z preserves local interpretation', () {
      final (lo, _) = parseScope('[2025-06-01T09:00:00,2025-06-01T17:00:00)');
      expect(lo, isNotNull);
      // Without Z, DateTime.parse treats as local
      expect(lo!.isUtc, isFalse);
    });

    test('empty parts return (null, null)', () {
      expect(parseScope('[,]'), (null, null));
    });
  });

  group('formatWindow', () {
    test('null returns em dash', () {
      expect(formatWindow(null), '\u2014');
    });

    test('malformed returns em dash', () {
      expect(formatWindow('bad'), '\u2014');
    });

    test('same day shows date once with centered dot', () {
      final result = formatWindow(
          '[2025-06-01T09:00:00Z,2025-06-01T17:00:00Z)');
      // Should contain the centered dot separator for same-day
      expect(result, contains('\u00b7'));
    });

    test('different days shows both dates', () {
      final result = formatWindow(
          '[2025-06-01T09:00:00Z,2025-06-02T17:00:00Z)');
      // Should NOT contain centered dot (different days)
      expect(result, isNot(contains('\u00b7')));
      // Should contain en dash separator
      expect(result, contains('\u2013'));
    });
  });

  group('formatScopeCompact', () {
    test('null returns em dash', () {
      expect(formatScopeCompact(null), '\u2014');
    });

    test('valid range always shows both dates', () {
      final result = formatScopeCompact(
          '[2025-06-01T09:00:00Z,2025-06-01T17:00:00Z)');
      // Always full format, no same-day optimization
      expect(result, contains('\u2013'));
    });
  });
}
