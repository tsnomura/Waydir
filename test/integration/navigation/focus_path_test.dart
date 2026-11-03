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

  String? cursorName() {
    final i = store.cursorIndex.value;
    final files = store.navigableFiles;
    if (i < 0 || i >= files.length) return null;

    return files[i].name;
  }

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_focus_');
    for (final n in ['a', 'b']) {
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

  test('puts the cursor on an item created after the last load', () async {
    final created = Directory(p.join(tmpDir.path, 'new'))..createSync();
    final focused = await store.focusPath(created.path);
    expect(focused, isTrue);
    expect(cursorName(), 'new');
    expect(store.selectedPaths.value, isEmpty);
  });

  test('matches paths case-insensitively on Windows', () async {
    final focused = await store.focusPath(p.join(tmpDir.path, 'B.TXT'));
    expect(focused, Platform.isWindows);
    if (Platform.isWindows) expect(cursorName(), 'b.txt');
  });

  test('leaves the cursor alone for a path outside the folder', () async {
    final before = store.cursorIndex.value;
    final focused = await store.focusPath(
      p.join(tmpDir.path, 'missing', 'x.txt'),
    );
    expect(focused, isFalse);
    expect(store.cursorIndex.value, before);
  });
}
