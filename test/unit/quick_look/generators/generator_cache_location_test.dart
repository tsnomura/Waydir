import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/features/quick_look/generators/generator_cache_location.dart';

void main() {
  group('longestMountFor', () {
    const mounts = [
      ('/', 'ext4'),
      ('/home', 'ext4'),
      ('/mnt/data', 'xfs'),
      ('/mnt/share', 'cifs'),
    ];

    test('picks the deepest mount containing the folder', () {
      expect(
        GeneratorCacheLocation.longestMountFor('/mnt/data/photos', mounts),
        ('/mnt/data', 'xfs'),
      );
      expect(GeneratorCacheLocation.longestMountFor('/home/u/docs', mounts), (
        '/home',
        'ext4',
      ));
      expect(GeneratorCacheLocation.longestMountFor('/usr/share', mounts), (
        '/',
        'ext4',
      ));
    });

    test('does not match a sibling that only shares a prefix', () {
      expect(
        GeneratorCacheLocation.longestMountFor('/mnt/database/x', mounts),
        ('/', 'ext4'),
      );
    });
  });

  test('a file on the same volume as the default cache uses it', () async {
    final tmp = Directory.systemTemp.createTempSync('waydir_cache_loc_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fallback = p.join(tmp.path, 'cache');
    final source = p.join(tmp.path, 'drawing.dxf');

    expect(
      await GeneratorCacheLocation.forSource(source, fallback: fallback),
      fallback,
    );
    expect(Directory(p.join(tmp.path, '.waydir-cache')).existsSync(), isFalse);
  });

  test('remote files use the default cache', () async {
    expect(
      await GeneratorCacheLocation.forSource(
        'sftp://host/home/u/a.dxf',
        fallback: '/cache',
      ),
      '/cache',
    );
  });
}
