@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_reader.dart';
import 'package:waydir/core/archive/archive_service.dart';

void main() {
  late Directory tmp;
  late String plainZip;
  late String lockedZip;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('waydir_arcpass');
    Archive build() => Archive()
      ..addFile(ArchiveFile.string('a/one.txt', 'one'))
      ..addFile(ArchiveFile.string('a/two.txt', 'two two two'));
    plainZip = p.join(tmp.path, 'plain.zip');
    File(plainZip).writeAsBytesSync(ZipEncoder().encode(build()));
    lockedZip = p.join(tmp.path, 'locked.zip');
    File(
      lockedZip,
    ).writeAsBytesSync(ZipEncoder(password: 'secret').encode(build()));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('detects encrypted zips', () {
    expect(ArchiveReader.isEncrypted(plainZip), isFalse);
    expect(ArchiveReader.isEncrypted(lockedZip), isTrue);
  });

  test('verifies the password', () {
    expect(ArchiveReader.verifyPassword(lockedZip, 'secret'), isTrue);
    expect(ArchiveReader.verifyPassword(lockedZip, 'wrong'), isFalse);
  });

  test('lists per-entry encryption flags', () {
    final locked = ArchiveReader.listEntries(lockedZip);
    expect(locked, hasLength(2));
    expect(locked.every((e) => !e.isDir && e.encrypted), isTrue);
    final plain = ArchiveReader.listEntries(plainZip);
    expect(plain, hasLength(2));
    expect(plain.every((e) => !e.encrypted), isTrue);
  });

  test('levelEntries exposes the per-entry flag', () {
    final all = ArchiveReader.listEntries(lockedZip);
    final level = ArchiveService.levelEntries(
      lockedZip,
      'a',
      all,
      DateTime.now(),
    );
    expect(level, hasLength(2));
    expect(level.every((e) => e.encrypted), isTrue);
  });

  test('extracts with the password', () {
    final staged = ArchiveReader.extractTree(
      lockedZip,
      'a',
      p.join(tmp.path, 'stage'),
      password: 'secret',
    );

    expect(File(p.join(staged, 'one.txt')).readAsStringSync(), 'one');
    expect(File(p.join(staged, 'two.txt')).readAsStringSync(), 'two two two');
  });
}
