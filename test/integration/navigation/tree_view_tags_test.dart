@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/tags/tag_store.dart';

void main() {
  late Directory tmpDir;
  late OperationStore operationStore;
  late NavigationStore store;
  late String previousMode;

  setUpAll(() async {
    final dbFile = File(
      p.join(
        Directory.systemTemp.createTempSync('waydir_settings_').path,
        'settings.sqlite',
      ),
    );
    await SettingsStore.instance.load(executor: NativeDatabase(dbFile));
    await TagStore.instance.load(SettingsStore.instance.db);
  });

  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!store.isLoading.value && store.treeLoadingPaths.value.isEmpty) {
        break;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  setUp(() async {
    previousMode = SettingsStore.instance.fileViewMode.value;
    tmpDir = Directory.systemTemp.createTempSync('waydir_tree_tags_');
    Directory(p.join(tmpDir.path, 'a')).createSync();
    File(p.join(tmpDir.path, 'a', 'nested.txt')).writeAsStringSync('x');
    File(p.join(tmpDir.path, 'top.txt')).writeAsStringSync('y');
    operationStore = OperationStore();
    store = NavigationStore(
      operationStore: operationStore,
      initialPath: tmpDir.path,
    );
    await settle();
    SettingsStore.instance.fileViewMode.value = 'tree';
    store.toggleTreeFolder(
      store.navigableFiles.firstWhere((f) => f.name == 'a'),
    );
    await settle();
  });

  tearDown(() {
    SettingsStore.instance.fileViewMode.value = previousMode;
    store.dispose();
    operationStore.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('items inside an expanded folder show and toggle their tags', () async {
    final tagId = TagStore.instance.tags.value.first.id;
    final nested = store.navigableFiles
        .firstWhere((f) => f.name == 'nested.txt')
        .path;

    await store.toggleTag([nested], tagId);
    await settle();
    expect(store.fileTags.value[nested], {tagId});

    await store.toggleTag([nested], tagId);
    await settle();
    expect(store.fileTags.value[nested], isNull);
  });

  test('tags of nested items load when the folder is expanded', () async {
    final tagId = TagStore.instance.tags.value.first.id;
    final nested = p.join(tmpDir.path, 'a', 'nested.txt');
    await SettingsStore.instance.db.addFileTag(nested, tagId);
    final a = store.navigableFiles.firstWhere((f) => f.name == 'a');
    store.toggleTreeFolder(a);
    await settle();
    store.treeChildren.value = {};
    store.toggleTreeFolder(a);
    await settle();

    expect(
      store.fileTags.value[store.navigableFiles
          .firstWhere((f) => f.name == 'nested.txt')
          .path],
      {tagId},
    );
  });
}
