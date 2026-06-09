import 'dart:async';

import 'package:clock/clock.dart';

class SyncPoller {
  SyncPoller({
    this.interval = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 60),
    Clock? clock,
    required this.poll,
    this.onTimeout,
  }) : _clock = clock ?? const Clock();

  final Duration interval;
  final Duration timeout;
  final Clock _clock;

  /// Called every [interval]. Return `true` to keep polling, `false` to stop.
  final Future<bool> Function() poll;

  /// Called once when [timeout] is exceeded.
  final void Function()? onTimeout;

  Timer? _timer;
  DateTime? _startTime;

  bool get isActive => _timer?.isActive ?? false;

  void start() {
    stop();
    _startTime = _clock.now();
    _timer = Timer.periodic(interval, (_) async {
      if (_clock.now().difference(_startTime!) > timeout) {
        stop();
        onTimeout?.call();
        return;
      }
      final keepGoing = await poll();
      if (!keepGoing) stop();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
