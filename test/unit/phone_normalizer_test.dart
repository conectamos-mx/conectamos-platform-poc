import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/phone_normalizer.dart';

void main() {
  // ── dialCode ────────────────────────────────────────────────────────────────

  group('PhoneNormalizer.dialCode', () {
    test('returns +52 for MX', () {
      expect(PhoneNormalizer.dialCode('MX'), '+52');
    });

    test('returns +1 for US', () {
      expect(PhoneNormalizer.dialCode('US'), '+1');
    });

    test('returns +502 for GT', () {
      expect(PhoneNormalizer.dialCode('GT'), '+502');
    });

    test('returns +57 for CO', () {
      expect(PhoneNormalizer.dialCode('CO'), '+57');
    });

    test('is case-insensitive', () {
      expect(PhoneNormalizer.dialCode('mx'), '+52');
      expect(PhoneNormalizer.dialCode('Mx'), '+52');
    });

    test('returns +1 fallback for unknown country', () {
      expect(PhoneNormalizer.dialCode('ZZ'), '+1');
    });
  });

  // ── validatePhone ──────────────────────────────────────────────────────────

  group('PhoneNormalizer.validatePhone', () {
    test('returns null for valid 10-digit MX number', () {
      expect(PhoneNormalizer.validatePhone('5559537449', 'MX'), isNull);
    });

    test('returns null for valid 7-digit number', () {
      expect(PhoneNormalizer.validatePhone('1234567', 'US'), isNull);
    });

    test('returns null for valid 15-digit number', () {
      expect(PhoneNormalizer.validatePhone('123456789012345', 'MX'), isNull);
    });

    test('returns error for empty digits', () {
      expect(PhoneNormalizer.validatePhone('', 'MX'), 'Teléfono requerido');
    });

    test('returns error for only non-digit chars', () {
      expect(PhoneNormalizer.validatePhone('---', 'MX'), 'Teléfono requerido');
    });

    test('returns error for too short (< 7)', () {
      expect(
          PhoneNormalizer.validatePhone('123456', 'MX'), 'Número demasiado corto');
    });

    test('returns error for too long (> 15)', () {
      expect(PhoneNormalizer.validatePhone('1234567890123456', 'MX'),
          'Número demasiado largo');
    });

    test('strips non-digits before validating', () {
      expect(PhoneNormalizer.validatePhone('(55) 5953-7449', 'MX'), isNull);
    });
  });

  // ── formatToE164 ──────────────────────────────────────────────────────────

  group('PhoneNormalizer.formatToE164', () {
    test('prepends +52 for raw MX digits', () {
      expect(PhoneNormalizer.formatToE164('5559537449', 'MX'), '+525559537449');
    });

    test('avoids doubling when digits already start with country prefix', () {
      expect(PhoneNormalizer.formatToE164('525559537449', 'MX'), '+525559537449');
    });

    test('strips non-digits from input', () {
      expect(
          PhoneNormalizer.formatToE164('(55) 5953-7449', 'MX'), '+525559537449');
    });

    test('returns empty string for empty input', () {
      expect(PhoneNormalizer.formatToE164('', 'MX'), '');
    });

    test('returns empty string for only non-digit chars', () {
      expect(PhoneNormalizer.formatToE164('---', 'MX'), '');
    });

    test('handles US number (+1)', () {
      expect(PhoneNormalizer.formatToE164('2125551234', 'US'), '+12125551234');
    });

    test('avoids doubling for US when digits start with 1', () {
      expect(PhoneNormalizer.formatToE164('12125551234', 'US'), '+12125551234');
    });

    test('handles GT 3-digit prefix', () {
      expect(PhoneNormalizer.formatToE164('23456789', 'GT'), '+50223456789');
    });

    test('uses +1 fallback for unknown country', () {
      expect(PhoneNormalizer.formatToE164('5559537449', 'ZZ'), '+15559537449');
    });

    test('is case-insensitive on country code', () {
      expect(PhoneNormalizer.formatToE164('5559537449', 'mx'), '+525559537449');
    });
  });

  // ── toWhatsappFormat ──────────────────────────────────────────────────────

  group('PhoneNormalizer.toWhatsappFormat', () {
    test('inserts 1 after +52 for MX number without it', () {
      expect(PhoneNormalizer.toWhatsappFormat('+525559537449'), '+5215559537449');
    });

    test('does NOT double-insert if 1 already present', () {
      expect(
          PhoneNormalizer.toWhatsappFormat('+5215559537449'), '+5215559537449');
    });

    test('does not modify non-MX numbers', () {
      expect(PhoneNormalizer.toWhatsappFormat('+12125551234'), '+12125551234');
      expect(PhoneNormalizer.toWhatsappFormat('+573001234567'), '+573001234567');
    });

    test('does not modify GT number starting with +502', () {
      expect(PhoneNormalizer.toWhatsappFormat('+50223456789'), '+50223456789');
    });
  });

  // ── toChatId ──────────────────────────────────────────────────────────────

  group('PhoneNormalizer.toChatId', () {
    test('MX: strips + and inserts 1 → 521...', () {
      expect(PhoneNormalizer.toChatId('+525559537449'), '5215559537449');
    });

    test('MX already with 1: strips + only', () {
      expect(PhoneNormalizer.toChatId('+5215559537449'), '5215559537449');
    });

    test('US: strips + only', () {
      expect(PhoneNormalizer.toChatId('+12125551234'), '12125551234');
    });

    test('handles input without + (no WhatsApp insertion — requires +52 prefix)', () {
      // toWhatsappFormat only triggers on '+52' prefix; without '+' it passes through
      expect(PhoneNormalizer.toChatId('525559537449'), '525559537449');
    });
  });

  // ── parsePhone ────────────────────────────────────────────────────────────

  group('PhoneNormalizer.parsePhone', () {
    test('parses MX E.164', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+525559537449');
      expect(iso, 'MX');
      expect(local, '5559537449');
    });

    test('parses US E.164', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+12125551234');
      expect(iso, 'US');
      expect(local, '2125551234');
    });

    test('parses GT (3-digit prefix) before US (1-digit)', () {
      // +502 should match GT, not US (+1 then 502...)
      final (iso, _) = PhoneNormalizer.parsePhone('+50223456789');
      expect(iso, 'GT');
    });

    test('parses CO', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+573001234567');
      expect(iso, 'CO');
      expect(local, '3001234567');
    });

    test('parses EC (3-digit prefix 593)', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+593991234567');
      expect(iso, 'EC');
      expect(local, '991234567');
    });

    test('falls back to MX for unrecognised prefix', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+999123456');
      expect(iso, 'MX');
      expect(local, '999123456');
    });

    test('strips non-digit chars before parsing', () {
      final (iso, local) = PhoneNormalizer.parsePhone('+52 55 5953 7449');
      expect(iso, 'MX');
      expect(local, '5559537449');
    });
  });

  // ── formatForDisplay ──────────────────────────────────────────────────────

  group('PhoneNormalizer.formatForDisplay', () {
    test('returns em-dash for null', () {
      expect(PhoneNormalizer.formatForDisplay(null), '\u2014');
    });

    test('returns em-dash for empty string', () {
      expect(PhoneNormalizer.formatForDisplay(''), '\u2014');
    });

    test('returns em-dash for whitespace-only', () {
      expect(PhoneNormalizer.formatForDisplay('   '), '\u2014');
    });

    test('formats MX number with flag, code, and grouped digits', () {
      final result = PhoneNormalizer.formatForDisplay('+525559537449');
      // Should contain MX flag emoji, +52, and grouped local digits
      expect(result, contains('+52'));
      expect(result, contains('55 5953 7449')); // 10-digit grouping
    });

    test('formats US number', () {
      final result = PhoneNormalizer.formatForDisplay('+12125551234');
      expect(result, contains('+1'));
      expect(result, contains('21 2555 1234')); // 10-digit grouping
    });

    test('returns raw string when digits do not match detected prefix', () {
      // Edge case: digits don't start with the detected country prefix
      // parsePhone falls back to MX (prefix 52), but digits don't start with 52
      final result = PhoneNormalizer.formatForDisplay('+999123456');
      // Digits: 999123456 → parsePhone → fallback MX, prefix 52
      // digits (999123456) do NOT start with '52' → returns raw string
      expect(result, '+999123456');
    });

    test('handles number with spaces in input', () {
      final result = PhoneNormalizer.formatForDisplay('+52 55 5953 7449');
      expect(result, contains('+52'));
      expect(result, contains('55 5953 7449'));
    });
  });
}
