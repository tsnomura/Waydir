import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/ui/theme/motion.dart';
import 'package:waydir/ui/widgets/app_spinner.dart';

void main() {
  tearDown(() => SettingsStore.instance.reduceMotion.value = 'system');

  group('detectRemoteDisplay', () {
    test('a local display is not remote', () {
      expect(detectRemoteDisplay({'DISPLAY': ':0'}), isFalse);
      expect(detectRemoteDisplay({'DISPLAY': ':1.0'}), isFalse);
      expect(detectRemoteDisplay({'DISPLAY': 'unix:0'}), isFalse);
      expect(detectRemoteDisplay({'WAYLAND_DISPLAY': 'wayland-0'}), isFalse);
      expect(detectRemoteDisplay({}), isFalse);
    });

    test('a forwarded X display is remote', () {
      expect(detectRemoteDisplay({'DISPLAY': 'localhost:10.0'}), isTrue);
      expect(detectRemoteDisplay({'DISPLAY': '192.168.1.5:0'}), isTrue);
    });

    test('an xpra session environment is remote', () {
      expect(
        detectRemoteDisplay({'DISPLAY': ':100', 'XPRA_SESSION_DIR': '/run/x'}),
        isTrue,
      );
    });
  });

  group('resolveReduceMotion', () {
    test('an explicit setting wins over the platform', () {
      expect(resolveReduceMotion('on', platformDisabled: false), isTrue);
      expect(resolveReduceMotion('off', platformDisabled: true), isFalse);
    });

    test('system follows the platform', () {
      expect(resolveReduceMotion('system', platformDisabled: true), isTrue);
    });
  });

  group('AppSpinner', () {
    Future<void> pumpSpinner(WidgetTester tester) =>
        tester.pumpWidget(const MaterialApp(home: Center(child: AppSpinner())));

    testWidgets('animates every frame by default', (tester) async {
      SettingsStore.instance.reduceMotion.value = 'off';
      await pumpSpinner(tester);
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('only repaints in steps under reduce motion', (tester) async {
      SettingsStore.instance.reduceMotion.value = 'on';
      await pumpSpinner(tester);
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
