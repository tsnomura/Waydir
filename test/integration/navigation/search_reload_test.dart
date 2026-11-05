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
    for (var i = 0; i < 100; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (!store.isLoading.value && !store.isSearching.value) break;
    }
    await Future.delayed(const Duration(milliseconds: 400));
    for (var i = 0; i < 100; i++) {
      if (!store.isSearching.value) break;
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  Set<String> names() => store.searchResults.value.map((e) => e.name).toSet();

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('waydir_search_reload_');
    Directory(p.join(tmpDir.path, 'sub')).createSync();
    File(p.join(tmpDir.path, 'sub', 'match_a.txt')).writeAsStringSync('a');
    operationStore = OperationStore();
    store = NavigationStore(
      operationStore: operationStore,
      initialPath: tmpDir.path,
    );
    await settle();
  });

  tearDown(() {
    store.closeSearch();
    store.dispose();
    operationStore.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('reload reruns a recursive search', () async {
    store.openSearch(recursive: true);
    store.setSearchMode('substring');
    store.setSearchQuery('match');
    await settle();
    expect(names(), {'match_a.txt'});

    File(p.join(tmpDir.path, 'sub', 'match_b.txt')).writeAsStringSync('b');
    await store.reload();
    await settle();

    expect(names(), {'match_a.txt', 'match_b.txt'});
  });
}
