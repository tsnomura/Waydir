@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/drives/drive_store.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/tabs/tab_strip.dart';
import 'package:waydir/features/tabs/tabs_store.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  late Directory tmpDir;
  late OperationStore ops;
  late TabsStore tabs;

  setUpAll(() async {
    final dbFile = File(
      p.join(
        Directory.systemTemp.createTempSync('waydir_settings_').path,
        'settings.sqlite',
      ),
    );
    await SettingsStore.instance.load(executor: NativeDatabase(dbFile));
    driveStore.drives.value;
  });

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('waydir_tab_strip_');
    final paths = [
      for (var i = 0; i < 12; i++)
        (Directory(
          p.join(tmpDir.path, 'folder_with_a_long_name_$i'),
        )..createSync()).path,
    ];
    ops = OperationStore();
    tabs = TabsStore.fromPaths(operationStore: ops, paths: paths);
  });

  tearDown(() {
    ops.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Rect activeRect(WidgetTester tester) {
    final name = p.basename(tabs.activeTab.value.store.currentPath.value);

    return tester.getRect(find.text(name).first);
  }

  Future<void> pumpStrip(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 400, child: TabStrip(tabsStore: tabs)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (final tab in tabs.tabs.value) {
      tab.store.dispose();
    }
    await tester.pump(const Duration(seconds: 5));
  }

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  testWidgets('a newly opened tab is scrolled into view', (tester) async {
    await pumpStrip(tester);
    expect(scrollOffset(tester), 0);

    final path = (Directory(
      p.join(tmpDir.path, 'opened_from_wd'),
    )..createSync()).path;
    tabs.addTab(path);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(activeRect(tester).right, lessThanOrEqualTo(400));
    expect(activeRect(tester).left, greaterThanOrEqualTo(0));

    await cleanUp(tester);
  });

  testWidgets('switching tabs or scrolling by hand is left alone', (
    tester,
  ) async {
    await pumpStrip(tester);

    tabs.activeIndex.value = tabs.tabs.value.length - 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(scrollOffset(tester), 0);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(scrollOffset(tester), 300);

    await cleanUp(tester);
  });
}
