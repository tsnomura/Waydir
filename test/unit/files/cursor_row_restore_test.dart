import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/files/file_view.dart';
import 'package:waydir/features/files/scroll_link.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  late ScrollLink link;

  setUp(() => link = ScrollLink());

  Widget listApp({required String path, required int cursor}) {
    final files = [
      for (var i = 0; i < 300; i++)
        FileEntry(
          name: 'file_$i.txt',
          path: '$path/file_$i.txt',
          type: FileItemType.file,
          size: i,
          modified: DateTime(2026, 1, 1),
        ),
    ];

    return MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 480,
          child: FileList(
            files: files,
            currentPath: path,
            scrollLink: link,
            cursorIndex: cursor,
            onSelect: (_) {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
  }

  ScrollPosition listPosition(WidgetTester tester) {
    final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
    for (final s in states) {
      if (s.position.axis == Axis.vertical) return s.position;
    }
    throw StateError('no vertical scrollable');
  }

  double itemExtent(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).itemExtent!;

  double rowTop(WidgetTester tester, int index) =>
      SettingsStore.instance.fileListVerticalSpacing.value.toDouble() +
      index * itemExtent(tester);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('reports the cursor row relative to the viewport top', (
    tester,
  ) async {
    await tester.pumpWidget(listApp(path: '/a', cursor: 100));
    await settle(tester);
    final ext = itemExtent(tester);
    listPosition(tester).jumpTo(rowTop(tester, 100) - 4 * ext);
    await tester.pump();

    expect(link.cursorRowFor('/a'), moreOrLessEquals(4, epsilon: 0.01));
  });

  testWidgets('a requested cursor row puts the cursor back at that row', (
    tester,
  ) async {
    link.requestCursorRow('/a', 5);
    await tester.pumpWidget(listApp(path: '/a', cursor: 120));
    await settle(tester);

    final ext = itemExtent(tester);
    expect(
      listPosition(tester).pixels,
      moreOrLessEquals(rowTop(tester, 120) - 5 * ext, epsilon: 1),
    );
    expect(link.takeCursorRow('/a'), isNull);
  });

  testWidgets('without a request the cursor is only scrolled into view', (
    tester,
  ) async {
    await tester.pumpWidget(listApp(path: '/a', cursor: 120));
    await settle(tester);

    final position = listPosition(tester);
    final ext = itemExtent(tester);
    final rowGap = SettingsStore.instance.fileListVerticalSpacing.value
        .toDouble();
    expect(
      position.pixels,
      moreOrLessEquals(
        rowTop(tester, 120) + ext - rowGap - position.viewportDimension,
        epsilon: 1,
      ),
    );
  });
}
