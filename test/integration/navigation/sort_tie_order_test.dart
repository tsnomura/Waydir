@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/fs/file_sort.dart';
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

  List<String> names() => [for (final f in store.visibleFiles.value) f.name];

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_sort_');
    for (final n in ['a.txt', 'b.txt', 'c.txt']) {
      File(p.join(tmpDir.path, n)).writeAsStringSync('xyz');
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

  test('a new sort key keeps the previous order within ties', () async {
    store.setSortKey(SortKey.name);
    store.setSortAscending(false);
    expect(names(), ['c.txt', 'b.txt', 'a.txt']);

    store.setSortKey(SortKey.size);

    expect(names(), ['c.txt', 'b.txt', 'a.txt']);
  });

  test('reading the list again does not change its order', () async {
    store.setSortKey(SortKey.name);
    store.setSortAscending(false);
    store.setSortKey(SortKey.size);
    final first = names();

    store.showHidden.value = !store.showHidden.value;

    expect(names(), first);
    expect(names(), first);
  });
}
