import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import 'package:waydir/ui/overlays/context_menu.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  final items = [
    ContextMenuItem(icon: WaydirIconsRegular.copy, label: 'One', action: 'one'),
    ContextMenuItem(
      icon: WaydirIconsRegular.copy,
      label: 'More',
      action: 'more',
      children: [
        ContextMenuItem(
          icon: WaydirIconsRegular.copy,
          label: 'Nested',
          action: 'nested',
        ),
      ],
    ),
  ];

  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;

              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    return ctx;
  }

  Future<TestGesture> openWithSubmenu(
    WidgetTester tester,
    BuildContext ctx, {
    void Function(String)? onSelect,
  }) async {
    showContextMenu(
      context: ctx,
      position: const Offset(20, 20),
      items: items,
      onSelect: onSelect ?? (_) {},
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.text('More')));
    await tester.pumpAndSettle();
    expect(find.text('Nested'), findsOneWidget);

    return mouse;
  }

  tearDown(dismissAllContextMenus);

  testWidgets('Escape clears the menu and its submenu', (tester) async {
    final ctx = await pump(tester);
    final mouse = await openWithSubmenu(tester, ctx);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(find.text('Nested'), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('a click outside clears the menu and its submenu', (
    tester,
  ) async {
    final ctx = await pump(tester);
    final mouse = await openWithSubmenu(tester, ctx);

    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(find.text('Nested'), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('a click inside the submenu still selects', (tester) async {
    final ctx = await pump(tester);
    String? picked;
    final mouse = await openWithSubmenu(
      tester,
      ctx,
      onSelect: (a) => picked = a,
    );

    await tester.tap(find.text('Nested'));
    await tester.pumpAndSettle();

    expect(picked, 'nested');
    expect(find.text('One'), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('hovering a closed menu before it is gone opens no submenu', (
    tester,
  ) async {
    final ctx = await pump(tester);
    showContextMenu(
      context: ctx,
      position: const Offset(20, 20),
      items: items,
      onSelect: (_) {},
    );
    await tester.pumpAndSettle();
    final more = tester.getCenter(find.text('More'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));

    dismissAllContextMenus();
    await mouse.moveTo(more);
    await tester.pumpAndSettle();

    expect(find.text('One'), findsNothing);
    expect(find.text('Nested'), findsNothing);
    await mouse.removePointer();
  });
}
