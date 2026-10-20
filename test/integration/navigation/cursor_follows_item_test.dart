@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/core/fs/file_sort.dart';
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

  String? cursorName() {
    final i = store.cursorIndex.value;
    final files = store.navigableFiles;
    if (i < 0 || i >= files.length) return null;

    return files[i].name;
  }

  void putCursorOn(String name) {
    final idx = store.navigableFiles.indexWhere((f) => f.name == name);
    store.cursorIndex.value = idx;
    store.anchorIndex.value = idx;
  }

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_cursor_');
    for (final n in ['a', 'b', 'c', 'd', 'e']) {
      Directory(p.join(tmpDir.path, n)).createSync();
    }
    for (final n in ['c', 'e', 'a', 'd', 'b']) {
      await Future.delayed(const Duration(milliseconds: 30));
      File(p.join(tmpDir.path, n, 'touch.txt')).writeAsStringSync(n);
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

  for (final back in ['goUp', 'goBack']) {
    test('$back returns the cursor to the folder that was entered', () async {
      putCursorOn('c');
      store.onOpen(store.visibleFiles.value[store.cursorIndex.value]);
      await settle();
      back == 'goUp' ? store.goUp() : store.goBack();
      await settle();

      expect(cursorName(), 'c');
    });
  }

  test('changing the sort key keeps the cursor on the same file', () {
    putCursorOn('b');
    store.setSortKey(SortKey.date);

    expect(store.visibleFiles.value.map((f) => f.name).first, isNot('a'));
    expect(cursorName(), 'b');
    expect(store.visibleFiles.value[store.anchorIndex.value].name, 'b');
  });

  test('changing the sort direction keeps the cursor on the same file', () {
    putCursorOn('b');
    store.setSortAscending(false);

    expect(store.visibleFiles.value.first.name, 'e');
    expect(cursorName(), 'b');
  });

  test('cycling the sort column keeps the cursor on the same file', () {
    putCursorOn('d');
    store.cycleSortColumn(SortKey.name);

    expect(store.visibleFiles.value.first.name, 'e');
    expect(cursorName(), 'd');
  });

  test(
    'an item appearing above the cursor keeps the cursor in place',
    () async {
      putCursorOn('c');
      Directory(p.join(tmpDir.path, 'aa')).createSync();
      await store.refresh();
      await settle();

      expect(store.visibleFiles.value[1].name, 'aa');
      expect(cursorName(), 'c');
    },
  );

  test(
    'deleting the cursor item moves the cursor to the nearest item',
    () async {
      putCursorOn('c');
      Directory(p.join(tmpDir.path, 'c')).deleteSync(recursive: true);
      await store.refresh();
      await settle();

      expect(cursorName(), 'd');
    },
  );

  test('going up lands on the folder that was left', () async {
    putCursorOn('a');
    store.navigateTo(p.join(tmpDir.path, 'c'));
    await settle();
    store.goUp();
    await settle();

    expect(cursorName(), 'c');
  });

  test('going back restores the remembered cursor', () async {
    putCursorOn('a');
    store.navigateTo(p.join(tmpDir.path, 'c'));
    await settle();
    store.goBack();
    await settle();

    expect(cursorName(), 'a');
  });

  test('a folder sort is applied together with its listing', () async {
    await SettingsStore.instance.db.setFolderSortPref(
      tmpDir.path,
      sortKey: 'date',
      sortAscending: false,
    );
    putCursorOn('c');
    store.onOpen(store.visibleFiles.value[store.cursorIndex.value]);
    await settle();
    final seen = <String>[];
    final dispose = effect(() {
      final names = store.visibleFiles.value.map((f) => f.name).join(',');
      if (names.contains('a')) seen.add(names);
    });
    store.goBack();
    await settle();
    dispose();

    expect(seen.toSet(), {'b,d,a,e,c'});
    expect(cursorName(), 'c');
  });

  test(
    'leaving a folder does not re-sort it before the next one shows',
    () async {
      await SettingsStore.instance.db.setFolderSortPref(
        tmpDir.path,
        sortKey: 'date',
        sortAscending: false,
      );
      store.dispose();
      store = NavigationStore(
        operationStore: operationStore,
        initialPath: tmpDir.path,
      );
      await settle();
      final seen = <String>[];
      final dispose = effect(() {
        final names = store.visibleFiles.value.map((f) => f.name).join(',');
        if (names.contains('a')) seen.add(names);
      });
      putCursorOn('c');
      store.onOpen(store.visibleFiles.value[store.cursorIndex.value]);
      await settle();
      dispose();

      expect(seen.toSet(), {'b,d,a,e,c'});
    },
  );

  test('saving the folder state lets a new tab restore the cursor', () async {
    putCursorOn('d');
    await store.saveFolderState();
    store.dispose();
    store = NavigationStore(
      operationStore: operationStore,
      initialPath: tmpDir.path,
    );
    await settle();

    expect(cursorName(), 'd');
  });

  test('the cursor row on screen is saved and requested on return', () async {
    putCursorOn('c');
    store.scrollLink.reportCursorRow(tmpDir.path, 3.5);
    store.navigateTo(p.join(tmpDir.path, 'a'));
    await settle();
    store.goBack();
    await settle();

    expect(cursorName(), 'c');
    expect(store.scrollLink.takeCursorRow(tmpDir.path), 3.5);
  });

  group('tree view', () {
    late String previousMode;

    Future<void> expandNested() async {
      Directory(p.join(tmpDir.path, 'a', 'sub')).createSync();
      File(
        p.join(tmpDir.path, 'a', 'sub', 'deep.txt'),
      ).writeAsStringSync('deep');
      SettingsStore.instance.fileViewMode.value = 'tree';
      store.toggleTreeFolder(
        store.navigableFiles.firstWhere((f) => f.name == 'a'),
      );
      await settle();
      store.toggleTreeFolder(
        store.navigableFiles.firstWhere((f) => f.name == 'sub'),
      );
      await settle();
      putCursorOn('deep.txt');
    }

    setUp(() {
      previousMode = SettingsStore.instance.fileViewMode.value;
    });

    test(
      'nested expansion and a deep cursor come back after going back',
      () async {
        await expandNested();
        store.navigateTo(p.join(tmpDir.path, 'c'));
        await settle();
        store.goBack();
        await settle();

        expect(store.treeExpandedPaths.value, {
          p.join(tmpDir.path, 'a'),
          p.join(tmpDir.path, 'a', 'sub'),
        });
        expect(cursorName(), 'deep.txt');
      },
    );

    test('nested expansion and a deep cursor survive a new store', () async {
      await expandNested();
      await store.saveFolderState();
      store.dispose();
      store = NavigationStore(
        operationStore: operationStore,
        initialPath: tmpDir.path,
      );
      await settle();

      expect(cursorName(), 'deep.txt');
      expect(
        store.navigableFiles.map((f) => f.name),
        containsAllInOrder(['a', 'sub', 'deep.txt', 'touch.txt', 'b']),
      );
    });

    tearDown(() {
      SettingsStore.instance.fileViewMode.value = previousMode;
    });

    test('switching between list and tree keeps the cursor item', () {
      putCursorOn('c');
      SettingsStore.instance.fileViewMode.value = 'tree';
      expect(cursorName(), 'c');
      SettingsStore.instance.fileViewMode.value = 'list';
      expect(cursorName(), 'c');
    });

    test('expanding a folder above the cursor keeps the cursor item', () async {
      SettingsStore.instance.fileViewMode.value = 'tree';
      putCursorOn('c');
      final a = store.navigableFiles.firstWhere((f) => f.name == 'a');
      store.toggleTreeFolder(a);
      await settle();

      expect(store.navigableFiles[1].name, 'touch.txt');
      expect(cursorName(), 'c');
    });
  });
}
