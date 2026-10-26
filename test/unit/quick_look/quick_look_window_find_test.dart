import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/code_editor.dart';
import 'package:waydir/features/quick_look/quick_look_window.dart';
import 'package:waydir/i18n/strings.g.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ql_window_find');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  FileEntry writeTextFile() {
    final lines = List.generate(
      120,
      (i) => i % 12 == 0 ? 'needle in the hay' : 'line $i',
    );
    final file = File('${tmp.path}/findme.txt');
    file.writeAsStringSync(lines.join('\n'));

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
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> openFindAndType(WidgetTester tester, String pattern) async {
    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, pattern);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    });
    await tester.pump();
  }

  testWidgets('search button appears for text previews', (tester) async {
    await pumpWindow(tester, writeTextFile());
    expect(find.byTooltip(t.quickLook.search), findsOneWidget);
    await unmountWindow(tester);
  });

  testWidgets('ctrl+f opens the find popup and steps through matches', (
    tester,
  ) async {
    await pumpWindow(tester, writeTextFile());
    await openFindAndType(tester, 'needle');
    expect(find.text('1/10'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('2/10'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);

    await unmountWindow(tester);
  });

  testWidgets('escape closes the find popup without closing the window', (
    tester,
  ) async {
    await pumpWindow(tester, writeTextFile());
    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    });
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(QuickLookWindow), findsOneWidget);

    await unmountWindow(tester);
  });

  testWidgets('a pattern without matches reports no matches', (tester) async {
    await pumpWindow(tester, writeTextFile());
    await openFindAndType(tester, 'zzz-nope');
    expect(find.text(t.quickLook.searchNoMatches), findsOneWidget);
    await unmountWindow(tester);
  });

  testWidgets('search button is absent for binary files', (tester) async {
    final file = File('${tmp.path}/blob.bin');
    file.writeAsBytesSync(List.generate(64, (i) => i % 7));
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
    await tester.pump();
    expect(find.byTooltip(t.quickLook.search), findsNothing);
    await unmountWindow(tester);
  });
}
