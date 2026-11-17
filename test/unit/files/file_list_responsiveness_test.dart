import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/files/file_view.dart';
import 'package:waydir/ui/theme/app_theme.dart';

FileEntry _entry(String name, int size) => FileEntry(
  name: name,
  path: '/tmp/$name',
  type: FileItemType.file,
  size: size,
  modified: DateTime(2026),
);

Widget _app(
  List<FileEntry> files, {
  int cursor = -1,
  Set<String> selected = const {},
}) {
  return MaterialApp(
    theme: AppTheme.build(),
    home: Scaffold(
      body: SizedBox(
        width: 640,
        height: 480,
        child: FileList(
          files: files,
          currentPath: '/tmp',
          cursorIndex: cursor,
          selectedPaths: selected,
          onSelect: (_) {},
          onOpen: (_) {},
        ),
      ),
    ),
  );
}

ScrollPosition _listPosition(WidgetTester tester) {
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (s.position.axis == Axis.vertical) return s.position;
  }
  throw StateError('no vertical scrollable');
}

void main() {
  tearDown(() => SettingsStore.instance.reduceMotion.value = 'system');

  testWidgets('column widths follow a replaced file list', (tester) async {
    await tester.pumpWidget(_app([_entry('a.txt', 5)]));
    final narrow = tester.getSize(find.text('5 B')).width;

    await tester.pumpWidget(
      _app([_entry('a.txt', 5), _entry('b.bin', 1024 * 1024 * 1000)]),
    );
    final wide = tester.getSize(find.text('5 B')).width;

    expect(wide, greaterThan(narrow));
    expect(tester.getSize(find.text('1000.0 MB')).width, wide);
  });

  testWidgets('column widths stay put when only the cursor moves', (
    tester,
  ) async {
    final files = [_entry('a.txt', 5), _entry('b.bin', 1024 * 1024 * 1000)];
    await tester.pumpWidget(_app(files, cursor: 0));
    final before = tester.getSize(find.text('5 B')).width;

    await tester.pumpWidget(_app(files, cursor: 1));

    expect(tester.getSize(find.text('5 B')).width, before);
  });

  testWidgets('scrollbar marks follow the marked set', (tester) async {
    final files = [for (var i = 0; i < 200; i++) _entry('f$i.txt', i)];
    bool hasMarks() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((p) => '${p.painter.runtimeType}' == '_ScrollbarMarksPainter');

    await tester.pumpWidget(_app(files));
    await tester.pump();
    expect(hasMarks(), isFalse);

    await tester.pumpWidget(_app(files, selected: {files[150].path}));
    await tester.pump();
    expect(hasMarks(), isTrue);

    await tester.pumpWidget(_app(files));
    await tester.pump();
    expect(hasMarks(), isFalse);
  });

  Future<int> framesToReveal(WidgetTester tester) async {
    final files = [for (var i = 0; i < 300; i++) _entry('f$i.txt', i)];
    final cursor = ValueNotifier(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 480,
            child: ValueListenableBuilder<int>(
              valueListenable: cursor,
              builder: (_, index, _) => FileList(
                files: files,
                currentPath: '/tmp',
                cursorIndex: index,
                onSelect: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    cursor.value = 200;
    var frames = 0;
    do {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    } while (tester.binding.hasScheduledFrame);

    expect(_listPosition(tester).pixels, greaterThan(0));

    return frames;
  }

  testWidgets('the cursor row is revealed in one step under reduce motion', (
    tester,
  ) async {
    SettingsStore.instance.reduceMotion.value = 'on';

    expect(await framesToReveal(tester), lessThanOrEqualTo(3));
  });

  testWidgets('the cursor row reveal animates by default', (tester) async {
    SettingsStore.instance.reduceMotion.value = 'off';

    expect(await framesToReveal(tester), greaterThan(3));
  });
}
