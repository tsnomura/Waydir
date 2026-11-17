import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:waydir/core/platform/app_activity.dart';

void main() {
  test('lifecycle states map to activity levels', () {
    expect(activityLevelFor(null), AppActivityLevel.active);
    expect(
      activityLevelFor(AppLifecycleState.resumed),
      AppActivityLevel.active,
    );
    expect(
      activityLevelFor(AppLifecycleState.inactive),
      AppActivityLevel.background,
    );
    expect(activityLevelFor(AppLifecycleState.hidden), AppActivityLevel.hidden);
    expect(activityLevelFor(AppLifecycleState.paused), AppActivityLevel.hidden);
  });

  group('ActivityPoller', () {
    late Signal<AppActivityLevel> level;
    late int polls;
    late ActivityPoller poller;

    void start() {
      level = signal(AppActivityLevel.active);
      polls = 0;
      poller = ActivityPoller(
        interval: const Duration(seconds: 3),
        backgroundEvery: 5,
        level: level,
        onPoll: () => polls++,
      )..start();
    }

    testWidgets('polls every interval while focused', (tester) async {
      start();
      await tester.pump(const Duration(seconds: 9));

      expect(polls, 3);
      poller.dispose();
    });

    testWidgets('polls less often while unfocused', (tester) async {
      start();
      level.value = AppActivityLevel.background;
      await tester.pump(const Duration(seconds: 30));

      expect(polls, 2);
      poller.dispose();
    });

    testWidgets('stops while hidden and polls at once when focused again', (
      tester,
    ) async {
      start();
      level.value = AppActivityLevel.hidden;
      await tester.pump(const Duration(seconds: 60));
      expect(polls, 0);

      level.value = AppActivityLevel.active;
      expect(polls, 1);

      await tester.pump(const Duration(seconds: 3));
      expect(polls, 2);
      poller.dispose();
    });

    testWidgets('going from unfocused to hidden does not poll', (tester) async {
      start();
      level.value = AppActivityLevel.background;
      level.value = AppActivityLevel.hidden;

      expect(polls, 0);
      poller.dispose();
    });
  });
}
