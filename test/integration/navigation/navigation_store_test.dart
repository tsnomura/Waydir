@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';

void main() {
  group('NavigationStore entered paths', () {
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

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('waydir_nav_');
      operationStore = OperationStore();
      store = NavigationStore(
        operationStore: operationStore,
        initialPath: tmpDir.path,
      );
    });

    tearDown(() {
      store.dispose();
      operationStore.dispose();
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('does not navigate to a missing path', () async {
      final missing = p.join(tmpDir.path, 'missing');

      final ok = await store.navigateToEnteredPath(missing);

      expect(ok, isFalse);
      expect(store.currentPath.value, tmpDir.path);
      expect(store.selectedPaths.value, isEmpty);
    });

    test('navigates to a file parent and selects the file', () async {
      final child = Directory(p.join(tmpDir.path, 'child'))..createSync();
      final file = File(p.join(child.path, 'note.txt'))
        ..writeAsStringSync('content');

      final ok = await store.navigateToEnteredPath(file.path);

      expect(ok, isTrue);
      expect(store.currentPath.value, child.path);
      expect(store.selectedPaths.value, {file.path});
    });

    test('multi rename reports progress for each renamed file', () async {
      final first = File(p.join(tmpDir.path, 'one.txt'))
        ..writeAsStringSync('1');
      final second = File(p.join(tmpDir.path, 'two.txt'))
        ..writeAsStringSync('2');
      final progress = <({int processed, int total, String current})>[];

      final outcome = await store.multiRename(
        [
          (path: first.path, newName: 'renamed-one.txt'),
          (path: second.path, newName: 'renamed-two.txt'),
        ],
        onProgress: (processed, total, currentName) {
          progress.add((
            processed: processed,
            total: total,
            current: currentName,
          ));
        },
      );

      expect(outcome.succeeded, 2);
      expect(outcome.failed, 0);
      expect(progress.map((p) => p.processed), [1, 2]);
      expect(progress.every((p) => p.total == 2), isTrue);
      expect(File(p.join(tmpDir.path, 'renamed-one.txt')).existsSync(), isTrue);
      expect(File(p.join(tmpDir.path, 'renamed-two.txt')).existsSync(), isTrue);
    });

    test(
      'renamed file stays selected despite a stale cached folder selection',
      () async {
        final other = File(p.join(tmpDir.path, 'other.txt'))
          ..writeAsStringSync('o');
        await SettingsStore.instance.db.setFolderUiState(
          tmpDir.path,
          cursorPath: other.path,
          selectedPaths: jsonEncode([other.path]),
        );
        await store.refresh();

        final file = File(p.join(tmpDir.path, 'original.txt'))
          ..writeAsStringSync('content');
        await store.refresh();

        store.selectedPaths.value = {file.path};
        store.renamingPath.value = file.path;
        store.commitRename('renamed.txt');
        await Future.delayed(const Duration(milliseconds: 400));

        expect(store.selectedPaths.value, {p.join(tmpDir.path, 'renamed.txt')});
      },
    );
  });
}
