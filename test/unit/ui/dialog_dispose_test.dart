import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/ui/dialogs/dialog.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:waydir/ui/theme/app_theme.dart';

class _PatternsBody extends StatefulWidget {
  final TextEditingController text;
  final FocusNode focus;

  const _PatternsBody({required this.text, required this.focus});

  @override
  State<_PatternsBody> createState() => _PatternsBodyState();
}

class _PatternsBodyState extends State<_PatternsBody> {
  @override
  void dispose() {
    widget.text.dispose();
    widget.focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.text,
      focusNode: widget.focus,
      autofocus: true,
    );
  }
}

void main() {
  testWidgets('dialog body disposes the controller of a focused field', (
    tester,
  ) async {
    final text = TextEditingController();
    final focus = FocusNode();
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
    await tester.pumpAndSettle();

    showCustomDialog<String>(
      context: ctx,
      title: 'Patterns',
      icon: WaydirIconsRegular.copy,
      body: _PatternsBody(text: text, focus: focus),
      actions: const [
        DialogAction(label: 'Cancel', color: Colors.white),
        DialogAction(label: 'Save', color: Colors.white),
      ],
    );
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(() => text.addListener(() {}), throwsA(isA<FlutterError>()));
  });
}
