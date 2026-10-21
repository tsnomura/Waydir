@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/fs/fs_worker_pool.dart';
import 'package:waydir/core/platform/platform_paths.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/navigation/bookmark_store.dart';

void main() {
  setUpAll(() async {
    final dbFile = File(
      p.join(
        Directory.systemTemp.createTempSync('waydir_settings_').path,
        'settings.sqlite',
      ),
    );
    await SettingsStore.instance.load(executor: NativeDatabase(dbFile));
    await FsWorkerPool.instance.ensureStarted();
  });

  Future<Map<String, bool>> settledMounted(String path) async {
    final store = BookmarkStore.instance;
    for (var i = 0; i < 100; i++) {
      if (store.mounted.value.containsKey(path)) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    return store.mounted.value;
  }

  test('bookmark presence is checked in the background', () async {
    final store = BookmarkStore.instance;
    final dir = Directory.systemTemp.createTempSync('waydir_bookmark_');
    final path = PlatformPaths.normalize(dir.path);

    expect(store.containsPath(path), isFalse);
    await store.addPath(path);
    expect(store.containsPath(path), isTrue);
    expect((await settledMounted(path))[path], isTrue);

    dir.deleteSync(recursive: true);
    store.mounted.value = {};
    await store.load();
    expect((await settledMounted(path))[path], isFalse);
  });

  test('a missing folder cannot be bookmarked', () async {
    final store = BookmarkStore.instance;
    final missing = PlatformPaths.normalize(
      p.join(Directory.systemTemp.path, 'waydir_no_such_bookmark_dir'),
    );

    await store.addPath(missing);

    expect(store.containsPath(missing), isFalse);
  });
}
