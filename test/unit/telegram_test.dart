import 'package:flutter_test/flutter_test.dart';
import 'package:conectamos_platform/core/utils/telegram.dart';

void main() {
  group('isTelegramExpired', () {
    test('null returns false', () {
      expect(isTelegramExpired(null), false);
    });

    test('invalid string returns false', () {
      expect(isTelegramExpired('not-a-date'), false);
    });

    test('future date returns false', () {
      final future = DateTime.now().add(const Duration(hours: 1)).toUtc();
      expect(isTelegramExpired(future.toIso8601String()), false);
    });

    test('past date returns true', () {
      final past = DateTime.now().subtract(const Duration(hours: 1)).toUtc();
      expect(isTelegramExpired(past.toIso8601String()), true);
    });

    test('uses UTC comparison (not local)', () {
      // A timestamp 1 second in the past (UTC) should be expired
      final justPast =
          DateTime.now().toUtc().subtract(const Duration(seconds: 1));
      expect(isTelegramExpired(justPast.toIso8601String()), true);

      // A timestamp 1 second in the future (UTC) should NOT be expired
      final justFuture =
          DateTime.now().toUtc().add(const Duration(seconds: 1));
      expect(isTelegramExpired(justFuture.toIso8601String()), false);
    });
  });
}
