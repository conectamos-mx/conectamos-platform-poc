import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/phone_normalizer.dart';

void main() {
  group('PhoneNormalizer.formatForDisplay', () {
    test('null → dash', () {
      expect(PhoneNormalizer.formatForDisplay(null), '—');
    });

    test('empty string → dash', () {
      expect(PhoneNormalizer.formatForDisplay(''), '—');
    });

    test('MX number formats with flag, code and 2-4-4 grouping', () {
      expect(
        PhoneNormalizer.formatForDisplay('525521062266'),
        '\u{1F1F2}\u{1F1FD} +52 55 2106 2266',
      );
    });

    test('AR number formats with flag and 3-digit grouping', () {
      final result = PhoneNormalizer.formatForDisplay('5491112345678');
      expect(result, startsWith('\u{1F1E6}\u{1F1F7} +54'));
      // 11 local digits → groups of 3: 911 123 456 78
      expect(result, '\u{1F1E6}\u{1F1F7} +54 911 123 456 78');
    });

    test('unrecognised prefix returns raw string', () {
      expect(PhoneNormalizer.formatForDisplay('999999999999'), '999999999999');
    });

    test('MX 10-digit local gets 2-4-4 grouping', () {
      expect(
        PhoneNormalizer.formatForDisplay('525530698230'),
        '\u{1F1F2}\u{1F1FD} +52 55 3069 8230',
      );
    });
  });
}
