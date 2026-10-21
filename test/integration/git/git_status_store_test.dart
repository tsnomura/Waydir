@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/features/git/git_status_store.dart';

void main() {
  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('waydir_git_');
    Process.runSync('git', ['init', '-q'], workingDirectory: repo.path);
    Directory(p.join(repo.path, 'sub', 'deep')).createSync(recursive: true);
    File(p.join(repo.path, 'a.txt')).writeAsStringSync('a');
  });

  tearDown(() {
    if (repo.existsSync()) repo.deleteSync(recursive: true);
  });

  test('a nested folder finds its repository and reports changes', () async {
    final store = GitStatusStore();
    addTearDown(store.dispose);

    await store.refresh(p.join(repo.path, 'sub', 'deep'));

    final status = store.status.value;
    expect(status, isNotNull);
    expect(status!.state, RepoState.clean);
  });

  test('an in-progress merge is reported', () async {
    final store = GitStatusStore();
    addTearDown(store.dispose);
    final gitDir = Process.runSync('git', [
      'rev-parse',
      '--absolute-git-dir',
    ], workingDirectory: repo.path).stdout.toString().trim();
    File(p.join(gitDir, 'MERGE_HEAD')).writeAsStringSync('0' * 40);

    await store.refresh(repo.path);

    expect(store.status.value?.state, RepoState.merging);
  });

  test('a folder outside any repository has no status', () async {
    final store = GitStatusStore();
    addTearDown(store.dispose);
    final outside = Directory.systemTemp.createTempSync('waydir_nogit_');
    addTearDown(() => outside.deleteSync(recursive: true));

    await store.refresh(outside.path);

    expect(store.status.value, isNull);
  });
}
