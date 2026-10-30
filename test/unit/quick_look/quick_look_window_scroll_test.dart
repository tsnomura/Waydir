import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/code_editor.dart';
import 'package:waydir/features/quick_look/markdown_preview.dart';
import 'package:waydir/features/quick_look/info_panel.dart';
import 'package:waydir/features/quick_look/quick_look_window.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ql_window_scroll');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  FileEntry writeTextFile(int lines) {
    final file = File('${tmp.path}/long.txt');
    file.writeAsStringSync(List.generate(lines, (i) => 'line $i').join('\n'));

    return FileEntry.fromFileSystemEntity(file);
  }

  Future<void> pumpWindow(WidgetTester tester, FileEntry entry) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Material(child: QuickLookWindow(entry: entry)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 20 && find.byType(CodeEditor).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(find.byType(CodeEditor), findsOneWidget);
    await tester.pumpAndSettle();
  }

  Future<void> unmountWindow(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Finder editorScrollable() => find.descendant(
    of: find.byType(CodeEditor),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(editorScrollable()).position;

  testWidgets('PageDown and PageUp scroll the preview by a page', (
    tester,
  ) async {
    await pumpWindow(tester, writeTextFile(300));
    final position = scrollPosition(tester);
    final viewport = position.viewportDimension;
    expect(position.pixels, 0.0);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageDown), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(viewport * 0.9, 1.0));

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.pageUp), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, 0.0);

    await unmountWindow(tester);
  });

  testWidgets('arrow keys scroll the preview by a smaller step', (
    tester,
  ) async {
    await pumpWindow(tester, writeTextFile(300));
    final position = scrollPosition(tester);
    final viewport = position.viewportDimension;

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(viewport * 0.15, 1.0));

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp), isTrue);
    await tester.pumpAndSettle();
    expect(position.pixels, 0.0);

    await unmountWindow(tester);
  });

  testWidgets('arrow keys keep scrolling after a page step', (tester) async {
    await pumpWindow(tester, writeTextFile(300));
    final position = scrollPosition(tester);
    final viewport = position.viewportDimension;

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final afterPage = position.pixels;

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown), isTrue);
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      closeTo(
        (afterPage + viewport * 0.15).clamp(0.0, position.maxScrollExtent),
        1.0,
      ),
    );

    await unmountWindow(tester);
  });

  testWidgets('arrow keys are ignored while a modifier is held', (
    tester,
  ) async {
    await pumpWindow(tester, writeTextFile(300));
    final position = scrollPosition(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    expect(
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown),
      isFalse,
    );
    await tester.pump();
    expect(position.pixels, 0.0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    await unmountWindow(tester);
  });

  testWidgets('left and right arrows step through sibling files', (
    tester,
  ) async {
    for (final name in ['a.txt', 'b.txt', 'c.txt']) {
      File('${tmp.path}/$name').writeAsStringSync('content of $name');
    }
    Directory('${tmp.path}/folder').createSync();
    await pumpWindow(
      tester,
      FileEntry.fromFileSystemEntity(File('${tmp.path}/b.txt')),
    );

    Future<void> step(LogicalKeyboardKey key) async {
      final handled = await tester.runAsync(() async {
        final handled = await tester.sendKeyEvent(key);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));

        return handled;
      });
      expect(handled, isTrue);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    await step(LogicalKeyboardKey.arrowRight);
    expect(find.text('c.txt'), findsWidgets);
    await step(LogicalKeyboardKey.arrowRight);
    expect(find.text('c.txt'), findsWidgets);
    await step(LogicalKeyboardKey.arrowLeft);
    await step(LogicalKeyboardKey.arrowLeft);
    expect(find.text('a.txt'), findsWidgets);
    await step(LogicalKeyboardKey.arrowLeft);
    expect(find.text('a.txt'), findsWidgets);

    await unmountWindow(tester);
  });

  testWidgets('F6 toggles between viewing and editing', (tester) async {
    for (final name in ['a.txt', 'b.txt', 'c.txt']) {
      File('${tmp.path}/$name').writeAsStringSync('content of $name');
    }
    await pumpWindow(
      tester,
      FileEntry.fromFileSystemEntity(File('${tmp.path}/b.txt')),
    );

    Future<void> press(LogicalKeyboardKey key, {bool control = false}) async {
      await tester.runAsync(() async {
        if (control) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.sendKeyEvent(key);
        if (control) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpAndSettle();
    }

    bool editorFocused() {
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (context == null) return false;

      return context.findAncestorWidgetOfExactType<CodeEditor>() != null;
    }

    expect(editorFocused(), isFalse);
    expect(find.text('Scroll'), findsOneWidget);
    await press(LogicalKeyboardKey.f6);
    expect(editorFocused(), isTrue);
    expect(find.text('Back to view'), findsOneWidget);
    await press(LogicalKeyboardKey.arrowRight);
    expect(find.text('b.txt'), findsWidgets);
    await press(LogicalKeyboardKey.arrowDown, control: true);
    expect(find.text('b.txt'), findsWidgets);

    await press(LogicalKeyboardKey.f6);
    expect(editorFocused(), isFalse);
    await press(LogicalKeyboardKey.arrowRight);
    expect(find.text('c.txt'), findsWidgets);

    await unmountWindow(tester);
  });

  Future<void> pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.runAsync(() async {
      await tester.sendKeyEvent(key);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('F6 switches markdown between rendered view and editing', (
    tester,
  ) async {
    final file = File('${tmp.path}/note.md')
      ..writeAsStringSync('# Title\n\nbody text\n');
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Material(
            child: QuickLookWindow(entry: FileEntry.fromFileSystemEntity(file)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);

    await pressKey(tester, LogicalKeyboardKey.f6);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text('Back to view'), findsOneWidget);

    await pressKey(tester, LogicalKeyboardKey.f6);
    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);
    expect(find.text('Scroll'), findsOneWidget);

    await unmountWindow(tester);
  });

  testWidgets('F7 toggles the properties panel', (tester) async {
    await pumpWindow(tester, writeTextFile(10));
    final before = find.byType(InfoPanel).evaluate().length;

    await pressKey(tester, LogicalKeyboardKey.f7);
    expect(find.byType(InfoPanel).evaluate().length, isNot(before));

    await pressKey(tester, LogicalKeyboardKey.f7);
    expect(find.byType(InfoPanel).evaluate().length, before);

    await unmountWindow(tester);
  });
}
