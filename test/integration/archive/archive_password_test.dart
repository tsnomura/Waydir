@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_reader.dart';

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
