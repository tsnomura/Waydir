import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/platform/user_tmp_dir.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('user_tmp_dir_test');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  String mode(String path) {
    return (FileStat.statSync(path).mode & 0x1FF).toRadixString(8);
  }

  test('path is /tmp/waydir-<uid> on Linux', () async {
    final uid = (Process.runSync('id', ['-u']).stdout as String).trim();

    expect(await UserTmpDir.path(), '/tmp/waydir-$uid');
  }, skip: !Platform.isLinux);

  test('path is %TEMP%\\waydir on Windows', () async {
    expect(
      await UserTmpDir.path(),
      p.join(Directory.systemTemp.path, 'waydir'),
    );
  }, skip: !Platform.isWindows);

  test('creates the directory on Windows', () async {
    final path = p.join(root.path, 'waydir');

    expect(await UserTmpDir.ensure(path), isTrue);
    expect(Directory(path).existsSync(), isTrue);
  }, skip: !Platform.isWindows);

  test('creates a missing directory as 0700', () async {
    final path = p.join(root.path, 'u');

    expect(await UserTmpDir.ensure(path), isTrue);
    expect(mode(path), '700');
  }, skip: !Platform.isLinux);

  test('tightens an existing own directory to 0700', () async {
    final path = p.join(root.path, 'u');
    Directory(path).createSync();
    Process.runSync('chmod', ['755', path]);

    expect(await UserTmpDir.ensure(path), isTrue);
    expect(mode(path), '700');
  }, skip: !Platform.isLinux);

  test('rejects a symlink', () async {
    final target = p.join(root.path, 'target');
    Directory(target).createSync();
    final path = p.join(root.path, 'u');
    Link(path).createSync(target);

    expect(await UserTmpDir.ensure(path), isFalse);
  }, skip: !Platform.isLinux);

  test('rejects a regular file', () async {
    final path = p.join(root.path, 'u');
    File(path).writeAsStringSync('');

    expect(await UserTmpDir.ensure(path), isFalse);
  }, skip: !Platform.isLinux);

  test('rejects a directory owned by someone else', () async {
    expect(await UserTmpDir.ensure('/'), isFalse);
  }, skip: !Platform.isLinux);
}
