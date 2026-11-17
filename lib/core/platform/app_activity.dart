import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:signals/signals.dart';

enum AppActivityLevel { active, background, hidden }

AppActivityLevel activityLevelFor(AppLifecycleState? state) {
  switch (state) {
    case null:
    case AppLifecycleState.resumed:
      return AppActivityLevel.active;
    case AppLifecycleState.inactive:
      return AppActivityLevel.background;
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
    case AppLifecycleState.detached:
      return AppActivityLevel.hidden;
  }
}

/// Whether the window is focused, visible but unfocused, or hidden, so
/// periodic background work can slow down or stop when nobody is looking.
class AppActivity {
  AppActivity._();

  static final instance = AppActivity._();

  final level = signal(AppActivityLevel.active);
  AppLifecycleListener? _listener;

  void attach() {
    if (_listener != null) return;
    level.value = activityLevelFor(WidgetsBinding.instance.lifecycleState);
    _listener = AppLifecycleListener(
      onStateChange: (state) => level.value = activityLevelFor(state),
    );
  }
}

/// A periodic poll that follows [AppActivity]: every [interval] while the
/// window is focused, every [backgroundEvery]th interval while it is visible
/// but unfocused, and not at all while it is hidden. Coming back to the
/// foreground polls at once.
class ActivityPoller {
  final Duration interval;
  final int backgroundEvery;
  final void Function() onPoll;
  final ReadonlySignal<AppActivityLevel> _level;
  Timer? _timer;
  void Function()? _disposer;
  int _tick = 0;

  ActivityPoller({
    required this.interval,
    required this.onPoll,
    this.backgroundEvery = 5,
    ReadonlySignal<AppActivityLevel>? level,
  }) : _level = level ?? AppActivity.instance.level;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => _onTick());
    var previous = _level.peek();
    _disposer = effect(() {
      final current = _level.value;
      final resumed =
          current == AppActivityLevel.active &&
          previous != AppActivityLevel.active;
      previous = current;
      if (resumed) untracked(onPoll);
    });
  }

  void _onTick() {
    _tick++;
    switch (_level.peek()) {
      case AppActivityLevel.active:
        onPoll();
      case AppActivityLevel.background:
        if (_tick % backgroundEvery == 0) onPoll();
      case AppActivityLevel.hidden:
        break;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _disposer?.call();
    _disposer = null;
  }
}
