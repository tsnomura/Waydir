@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';

void main() {
  late Directory tmpDir;
  late OperationStore operationStore;
  late NavigationStore store;

  setUpAll(() async {
    final dbFile = File(
      p.join(
        Directory.systemTemp.createTempSync('waydir_settings_').path,
        'settings.sqlite',
      ),
    );
    await SettingsStore.instance.load(executor: NativeDatabase(dbFile));
  });

  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (!store.isLoading.value) break;
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }

  String pathOf(String name) => p.join(tmpDir.path, name);

  void putCursorOn(String name) {
    store.cursorIndex.value = store.navigableFiles.indexWhere(
      (f) => f.name == name,
    );
  }

  List<String> targetNames() => [for (final e in store.targetEntries) e.name];

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_targets_');
    for (final n in ['a.txt', 'b.txt', 'c.txt']) {
      File(pathOf(n)).writeAsStringSync(n);
    }
    operationStore = OperationStore();
    store = NavigationStore(
      operationStore: operationStore,
      initialPath: tmpDir.path,
    );
    await settle();
  });

  tearDown(() {
    store.dispose();
    operationStore.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('targets the cursor item when nothing is marked', () {
    store.selectedPaths.value = {};
    putCursorOn('b.txt');

    expect(targetNames(), ['b.txt']);
  });

  test('targets the marks, not the cursor, when anything is marked', () {
    store.selectedPaths.value = {pathOf('a.txt'), pathOf('c.txt')};
    putCursorOn('b.txt');

    expect(targetNames(), ['a.txt', 'c.txt']);
  });

  test('flags marks that leave out the cursor item', () {
    store.selectedPaths.value = {pathOf('a.txt')};
    putCursorOn('b.txt');
    expect(store.marksExcludeCursor, isTrue);

    putCursorOn('a.txt');
    expect(store.marksExcludeCursor, isFalse);

    store.selectedPaths.value = {};
    putCursorOn('b.txt');
    expect(store.marksExcludeCursor, isFalse);
  });

  test('an override wins until it is cleared', () {
    store.selectedPaths.value = {pathOf('a.txt')};
    putCursorOn('c.txt');
    final c = store.cursorEntry.value!;

    store.setTargetOverride([c]);
    expect(targetNames(), ['c.txt']);

    store.setTargetOverride(null);
    expect(targetNames(), ['a.txt']);
  });

  test('deleting the cursor target keeps unrelated marks', () async {
    store.selectedPaths.value = {pathOf('a.txt')};
    putCursorOn('c.txt');

    store.deleteSelected(targets: [store.cursorEntry.value!]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(store.selectedPaths.value, {pathOf('a.txt')});
  });
}
