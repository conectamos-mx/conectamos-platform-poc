import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conectamos_platform/core/utils/sync_poller.dart';

void main() {
  group('SyncPoller', () {
    test('success: stops when poll returns false', () {
      fakeAsync((async) {
        int pollCount = 0;

        final poller = SyncPoller(
          interval: const Duration(seconds: 2),
          timeout: const Duration(seconds: 60),
          clock: async.getClock(DateTime(2026)),
          poll: () async {
            pollCount++;
            // First call: keep going. Second call: done.
            return pollCount < 2;
          },
        );

        poller.start();
        expect(poller.isActive, isTrue);

        // First tick at 2s → poll returns true (keep going)
        async.elapse(const Duration(seconds: 2));
        expect(pollCount, 1);
        expect(poller.isActive, isTrue);

        // Second tick at 4s → poll returns false (stop)
        async.elapse(const Duration(seconds: 2));
        expect(pollCount, 2);
        expect(poller.isActive, isFalse);

        // No more ticks after stop
        async.elapse(const Duration(seconds: 10));
        expect(pollCount, 2);
      });
    });

    test('timeout: stops and calls onTimeout after timeout exceeded', () {
      fakeAsync((async) {
        int pollCount = 0;
        bool timedOut = false;

        final poller = SyncPoller(
          interval: const Duration(seconds: 2),
          timeout: const Duration(seconds: 5),
          clock: async.getClock(DateTime(2026)),
          poll: () async {
            pollCount++;
            return true; // always keep going
          },
          onTimeout: () => timedOut = true,
        );

        poller.start();

        // 2s → poll #1 (within timeout)
        async.elapse(const Duration(seconds: 2));
        expect(pollCount, 1);
        expect(timedOut, isFalse);
        expect(poller.isActive, isTrue);

        // 4s → poll #2 (within timeout)
        async.elapse(const Duration(seconds: 2));
        expect(pollCount, 2);
        expect(timedOut, isFalse);
        expect(poller.isActive, isTrue);

        // 6s → timeout exceeded (5s), poller stops + onTimeout called
        async.elapse(const Duration(seconds: 2));
        expect(timedOut, isTrue);
        expect(poller.isActive, isFalse);
        // poll was NOT called because timeout check happens first
        expect(pollCount, 2);

        // No more ticks
        async.elapse(const Duration(seconds: 10));
        expect(pollCount, 2);
      });
    });

    test('dispose: cancels timer, no more ticks', () {
      fakeAsync((async) {
        int pollCount = 0;

        final poller = SyncPoller(
          interval: const Duration(seconds: 2),
          timeout: const Duration(seconds: 60),
          clock: async.getClock(DateTime(2026)),
          poll: () async {
            pollCount++;
            return true;
          },
        );

        poller.start();
        expect(poller.isActive, isTrue);

        // First tick
        async.elapse(const Duration(seconds: 2));
        expect(pollCount, 1);

        // Dispose
        poller.dispose();
        expect(poller.isActive, isFalse);

        // No more ticks after dispose
        async.elapse(const Duration(seconds: 20));
        expect(pollCount, 1);
      });
    });
  });
}
