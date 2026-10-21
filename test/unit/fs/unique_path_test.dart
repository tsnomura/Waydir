import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/fs/file_system_service.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('waydir_unique_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String at(String name) => p.join(dir.path, name);

  test('a free name is returned unchanged', () {
    expect(FileSystemService.uniquePath(at('mergers.zip')), at('mergers.zip'));
  });

  test('a taken file name is numbered before its extension', () {
    File(at('mergers.zip')).writeAsStringSync('');
    File(at('mergers (1).zip')).writeAsStringSync('');

    expect(
      FileSystemService.uniquePath(at('mergers.zip')),
      at('mergers (2).zip'),
    );
  });

  test('compound archive extensions stay whole', () {
    File(at('backup.tar.gz')).writeAsStringSync('');

    expect(
      FileSystemService.uniquePath(at('backup.tar.gz')),
      at('backup (1).tar.gz'),
    );
  });

  test('a folder is numbered at the end even with dots in its name', () {
    Directory(at('release.v1.2')).createSync();

    expect(
      FileSystemService.uniquePath(at('release.v1.2'), isFolder: true),
      at('release.v1.2 (1)'),
    );
  });

  test('the async variant gives the same result', () async {
    File(at('a.txt')).writeAsStringSync('');

    expect(
      await FileSystemService.uniquePathAsync(at('a.txt')),
      at('a (1).txt'),
    );
  });
}
