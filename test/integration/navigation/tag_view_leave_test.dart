@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/platform/platform_paths.dart';
import 'package:waydir/core/settings/settings_store.dart';
import 'package:waydir/features/navigation/navigation_store.dart';
import 'package:waydir/features/operations/operation_store.dart';
import 'package:waydir/features/tags/tag_path.dart';

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
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!store.isLoading.value) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> open(String initialPath) async {
    store = NavigationStore(
      operationStore: operationStore,
      initialPath: initialPath,
    );
    await settle();
  }

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('waydir_tag_leave_');
    operationStore = OperationStore();
  });

  tearDown(() {
    store.dispose();
    operationStore.dispose();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('leaving a tag view returns to the folder it was opened from', () async {
    await open(tmpDir.path);
    store.navigateTo(tagPathFor(1));
    await settle();
    store.navigateTo(tagPathFor(2));
    await settle();

    store.leaveTagView();
    await settle();

    expect(store.currentPath.value, tmpDir.path);
  });

  test('a tab that started in a tag view leaves to the home folder', () async {
    await open(tagPathFor(1));

    store.leaveTagView();
    await settle();

    expect(
      store.currentPath.value,
      PlatformPaths.normalize(PlatformPaths.homePath),
    );
  });

  test('going up from a tag view leaves it the same way', () async {
    await open(tmpDir.path);
    store.navigateTo(tagPathFor(3));
    await settle();

    store.goUp();
    await settle();

    expect(store.currentPath.value, tmpDir.path);
  });
}
