import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/ui/dialogs/dialog.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) {
            ctx = context;

            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();

    return ctx;
  }

  testWidgets('autofocused text field in a custom dialog gets primary focus', (
    tester,
  ) async {
    final ctx = await pumpApp(tester);
    final controller = TextEditingController();
    showCustomDialog<String>(
      context: ctx,
      title: 'Patterns',
      icon: WaydirIconsRegular.copy,
      body: TextField(controller: controller, autofocus: true),
      actions: const [
        DialogAction(label: 'Cancel', color: Colors.white),
        DialogAction(label: 'Save', color: Colors.white),
      ],
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasPrimaryFocus, isTrue);
    controller.dispose();
  });

  testWidgets('Enter confirms and Escape cancels when no field is focused', (
    tester,
  ) async {
    final ctx = await pumpApp(tester);
    String? result;
    final pending = showCustomDialog<String>(
      context: ctx,
      title: 'Confirm',
      icon: WaydirIconsRegular.copy,
      body: const SizedBox(width: 200, height: 40),
      actions: const [
        DialogAction(label: 'Cancel', color: Colors.white),
        DialogAction(label: 'Save', color: Colors.white),
      ],
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await pending;
    expect(result, 'Save');

    result = null;
    final pending2 = showCustomDialog<String>(
      context: ctx,
      title: 'Confirm',
      icon: WaydirIconsRegular.copy,
      body: const SizedBox(width: 200, height: 40),
      actions: const [
        DialogAction(label: 'Cancel', color: Colors.white),
        DialogAction(label: 'Save', color: Colors.white),
      ],
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await pending2;
    expect(result, 'Cancel');
  });
}
