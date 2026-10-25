import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/ui/theme/motion.dart';

void main() {
  final store = SettingsStore.instance;

  tearDown(() {
    store.reduceMotion.value = 'system';
  });

  Future<bool> reduceMotionFor(
    WidgetTester tester, {
    required bool disableAnimations,
  }) async {
    late bool result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (context) {
            result = context.reduceMotion;

            return const SizedBox.shrink();
          },
        ),
      ),
    );

    return result;
  }

  testWidgets('system setting follows MediaQuery.disableAnimations', (
    tester,
  ) async {
    store.reduceMotion.value = 'system';
    expect(await reduceMotionFor(tester, disableAnimations: false), isFalse);
    expect(await reduceMotionFor(tester, disableAnimations: true), isTrue);
  });

  testWidgets('forcing on overrides the OS setting', (tester) async {
    store.reduceMotion.value = 'on';
    expect(await reduceMotionFor(tester, disableAnimations: false), isTrue);
  });

  testWidgets('forcing off overrides the OS setting', (tester) async {
    store.reduceMotion.value = 'off';
    expect(await reduceMotionFor(tester, disableAnimations: true), isFalse);
  });
}
