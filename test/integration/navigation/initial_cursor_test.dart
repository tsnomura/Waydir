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
  NavigationStore? store;

  setUpAll(() async {
    final dbFile = File(
      p.join(
        Directory.systemTemp.createTempSync('waydir_settings_').path,
        'settings.sqlite',
      ),
    );
    await SettingsStore.instance.load(executor: NativeDatabase(dbFile));
  });

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('waydir_initial_cursor_');
    for (final n in ['a', 'b', 'c']) {
      File(p.join(tmpDir.path, '$n.txt')).writeAsStringSync(n);
    }
    operationStore = OperationStore();
  });

  tearDown(() {
    store?.dispose();
    store = null;
    operationStore.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  Future<NavigationStore> open({String? select, String? cursor}) async {
    final s = NavigationStore(
      operationStore: operationStore,
      initialPath: tmpDir.path,
      initialSelect: select,
      initialCursor: cursor,
    );
    store = s;
    for (var i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (!s.isLoading.value) break;
    }
    await Future.delayed(const Duration(milliseconds: 50));

    return s;
  }

  test(
    'initialCursor puts the cursor on the file without marking it',
    () async {
      final s = await open(cursor: p.join(tmpDir.path, 'b.txt'));

      expect(s.cursorEntry.value?.name, 'b.txt');
      expect(s.selectedPaths.value, isEmpty);
    },
  );

  test('initialSelect still marks the file', () async {
    final target = p.join(tmpDir.path, 'c.txt');
    final s = await open(select: target);

    expect(s.cursorEntry.value?.name, 'c.txt');
    expect(s.selectedPaths.value, {target});
  });
}
