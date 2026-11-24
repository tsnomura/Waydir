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
    await SettingsStore.instance.load(executor: NativeDatabase.memory());
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

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_place_cursor_');
    for (final n in ['a', 'b', 'c']) {
      File(p.join(tmpDir.path, '$n.txt')).writeAsStringSync(n);
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

  test('moves the cursor onto a listed file without marking it', () {
    store.placeCursorOn(p.join(tmpDir.path, 'c.txt'));

    expect(cursorName(), 'c.txt');
    expect(store.selectedPaths.value, isEmpty);
  });

  test('reloads to reach a file created after the last load', () async {
    final created = File(p.join(tmpDir.path, 'd.txt'))..writeAsStringSync('d');
    store.placeCursorOn(created.path);
    await settle();

    expect(cursorName(), 'd.txt');
    expect(store.selectedPaths.value, isEmpty);
  });

  test('closes an active search so the file is reachable', () async {
    store.openSearch();
    store.setSearchQuery('a');
    await settle();
    store.placeCursorOn(p.join(tmpDir.path, 'b.txt'));
    await settle();

    expect(store.searchActive.value, isFalse);
    expect(cursorName(), 'b.txt');
  });

  test('matches paths case-insensitively on Windows', () async {
    store.placeCursorOn(p.join(tmpDir.path, 'B.TXT'));
    await settle();

    if (Platform.isWindows) expect(cursorName(), 'b.txt');
  });
}
