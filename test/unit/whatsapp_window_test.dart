import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/whatsapp_window.dart';

void main() {
  group('whatsAppWindowOpen', () {
    test('null input returns false', () {
      expect(whatsAppWindowOpen(null), isFalse);
    });

    test('invalid string returns false', () {
      expect(whatsAppWindowOpen('not-a-date'), isFalse);
      expect(whatsAppWindowOpen(''), isFalse);
    });

    test('<24h ago returns true', () {
      final ts = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 23))
          .toIso8601String();
      expect(whatsAppWindowOpen(ts), isTrue);
    });

    test('>24h ago returns false', () {
      final ts = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      expect(whatsAppWindowOpen(ts), isFalse);
    });

    test('exactly 24h ago returns false (boundary)', () {
      final ts = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();
      expect(whatsAppWindowOpen(ts), isFalse);
    });

    test('input WITH Z suffix works correctly', () {
      final ts = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String(); // ends with Z
      expect(ts, endsWith('Z'));
      expect(whatsAppWindowOpen(ts), isTrue);
    });

    test('input WITHOUT Z suffix works correctly (same instant)', () {
      final now = DateTime.now().toUtc();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      // Build a string without Z — simulates a server that omits it
      final noZ =
          '${oneHourAgo.year}-${_pad(oneHourAgo.month)}-${_pad(oneHourAgo.day)}'
          'T${_pad(oneHourAgo.hour)}:${_pad(oneHourAgo.minute)}:${_pad(oneHourAgo.second)}';
      // DateTime.tryParse treats no-suffix as local, but .toUtc() normalizes
      expect(whatsAppWindowOpen(noZ), isTrue);
    });

    test('future timestamp returns true (window open)', () {
      final ts = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      expect(whatsAppWindowOpen(ts), isTrue);
    });
  });
}

String _pad(int n) => n.toString().padLeft(2, '0');
