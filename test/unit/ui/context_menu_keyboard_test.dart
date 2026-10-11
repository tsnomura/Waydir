import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:waydir/ui/overlays/context_menu.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  final items = [
    ContextMenuItem(icon: WaydirIconsRegular.copy, label: 'One', action: 'one'),
    ContextMenuItem.divider,
    ContextMenuItem(icon: WaydirIconsRegular.copy, label: 'Two', action: 'two'),
  ];

  Future<(BuildContext, FocusNode)> pump(WidgetTester tester) async {
    late BuildContext ctx;
    final owner = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: Focus(
            focusNode: owner,
            autofocus: true,
            child: Builder(
              builder: (context) {
                ctx = context;

                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return (ctx, owner);
  }

  testWidgets('arrow keys and Enter pick an item', (tester) async {
    final (ctx, _) = await pump(tester);
    String? picked;
    showContextMenu(
      context: ctx,
      position: const Offset(20, 20),
      items: items,
      keyboard: true,
      onSelect: (a) => picked = a,
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, 'two');
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('Escape closes the menu and returns focus', (tester) async {
    final (ctx, owner) = await pump(tester);
    showContextMenu(
      context: ctx,
      position: const Offset(20, 20),
      items: items,
      keyboard: true,
      onSelect: (_) {},
    );
    await tester.pumpAndSettle();
    expect(owner.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(owner.hasFocus, isTrue);
  });
}
