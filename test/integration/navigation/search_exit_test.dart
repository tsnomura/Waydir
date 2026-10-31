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

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_search_exit_');
    for (final n in ['a.txt', 'b.txt', 'c.txt']) {
      File(p.join(tmpDir.path, n)).writeAsStringSync(n);
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

  test('leaving search puts the cursor on the first row when unset', () {
    store.cursorIndex.value = -1;
    final before = store.searchExitRequest.value;

    store.focusFileListFromSearch();

    expect(store.cursorIndex.value, 0);
    expect(store.searchExitRequest.value, before + 1);
  });

  test('leaving search keeps an existing cursor', () {
    store.cursorIndex.value = 2;

    store.focusFileListFromSearch();

    expect(store.cursorIndex.value, 2);
  });
}
