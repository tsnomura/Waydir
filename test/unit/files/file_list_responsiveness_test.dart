import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals/signals.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/files/file_grid.dart';
import 'package:waydir/features/files/file_list_selection.dart';
import 'package:waydir/features/files/file_view.dart';
import 'package:waydir/ui/theme/app_theme.dart';

FileEntry _entry(String name, int size) => FileEntry(
  name: name,
  path: '/tmp/$name',
  type: FileItemType.file,
  size: size,
  modified: DateTime(2026),
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.build(),
  home: Scaffold(body: SizedBox(width: 640, height: 480, child: child)),
);

Widget _app(
  List<FileEntry> files, {
  int cursor = -1,
  Set<String> selected = const {},
}) {
  return _host(
    FileList(
      files: files,
      currentPath: '/tmp',
      selection: FileListSelection.fixed(
        cursorIndex: cursor,
        selectedPaths: selected,
      ),
      onSelect: (_) {},
      onOpen: (_) {},
    ),
  );
}

ScrollPosition _listPosition(WidgetTester tester) {
  for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
    if (s.position.axis == Axis.vertical) return s.position;
  }
  throw StateError('no vertical scrollable');
}

String _look(WidgetTester tester, String name) {
  final containers = tester.widgetList<Container>(
    find.ancestor(of: find.text(name), matching: find.byType(Container)),
  );

  return [
    for (final c in containers) '${c.decoration}|${c.foregroundDecoration}',
  ].join('\n');
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
    final marks = signal<Set<String>>({});
    bool hasMarks() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((p) => '${p.painter.runtimeType}' == '_ScrollbarMarksPainter');

    await tester.pumpWidget(
      _host(
        FileList(
          files: files,
          currentPath: '/tmp',
          selection: FileListSelection(
            cursorIndex: signal(-1),
            selectedPaths: marks,
          ),
          onSelect: (_) {},
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(hasMarks(), isFalse);

    marks.value = {files[150].path};
    await tester.pump();
    expect(hasMarks(), isTrue);

    marks.value = {};
    await tester.pump();
    expect(hasMarks(), isFalse);
  });

  group('row-level updates', () {
    final files = [for (var i = 0; i < 30; i++) _entry('f$i.txt', i)];

    Future<void> check(
      WidgetTester tester,
      Widget Function(FileListSelection selection, VoidCallback onBuild) view,
    ) async {
      final cursor = signal(0);
      final marks = signal<Set<String>>({});
      var builds = 0;
      await tester.pumpWidget(
        _host(
          view(
            FileListSelection(cursorIndex: cursor, selectedPaths: marks),
            () => builds++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cursorLook = _look(tester, 'f0.txt');
      final plainLook = _look(tester, 'f1.txt');
      expect(cursorLook, isNot(plainLook));
      expect(_look(tester, 'f2.txt'), plainLook);
      builds = 0;

      cursor.value = 1;
      await tester.pumpAndSettle();

      expect(_look(tester, 'f0.txt'), plainLook);
      expect(_look(tester, 'f1.txt'), cursorLook);

      marks.value = {files[2].path};
      await tester.pumpAndSettle();

      expect(_look(tester, 'f2.txt'), isNot(plainLook));
      expect(_look(tester, 'f3.txt'), plainLook);
      expect(builds, 0);
    }

    testWidgets('the list follows the cursor and marks without rebuilding', (
      tester,
    ) async {
      await check(
        tester,
        (selection, onBuild) => Builder(
          builder: (_) {
            onBuild();

            return FileList(
              files: files,
              currentPath: '/tmp',
              selection: selection,
              onSelect: (_) {},
              onOpen: (_) {},
            );
          },
        ),
      );
    });

    testWidgets('the grid follows the cursor and marks without rebuilding', (
      tester,
    ) async {
      await check(
        tester,
        (selection, onBuild) => Builder(
          builder: (_) {
            onBuild();

            return FileGrid(
              files: files,
              currentPath: '/tmp',
              selection: selection,
              onSelect: (_) {},
              onOpen: (_) {},
            );
          },
        ),
      );
    });
  });

  Future<int> framesToReveal(WidgetTester tester) async {
    final files = [for (var i = 0; i < 300; i++) _entry('f$i.txt', i)];
    final cursor = signal(0);
    await tester.pumpWidget(
      _host(
        FileList(
          files: files,
          currentPath: '/tmp',
          selection: FileListSelection(
            cursorIndex: cursor,
            selectedPaths: signal(const {}),
          ),
          onSelect: (_) {},
          onOpen: (_) {},
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
    expect(find.text('f200.txt'), findsOneWidget);

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
