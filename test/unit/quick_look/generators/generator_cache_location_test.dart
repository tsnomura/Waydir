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

  group('ownedAnchor', () {
    const me = 1000;
    const owners = {
      '/mnt/shared': 0,
      '/mnt/shared/alice': me,
      '/mnt/shared/alice/work': me,
      '/mnt/shared/alice/work/run1': me,
      '/mnt/shared/bob': 2000,
      '/mnt/shared/bob/shared': me,
      '/mnt/data': me,
      '/mnt/data/sub': me,
    };
    String? anchor(
      String root,
      String dir, {
      int? uid = me,
      Set<String> readOnly = const {},
    }) => GeneratorCacheLocation.ownedAnchor(
      root,
      dir,
      uid: uid,
      ownerOf: (path) => owners[path],
      writable: (path) => !readOnly.contains(path),
    );

    test('skips a shared root and takes the topmost folder the user owns', () {
      expect(
        anchor('/mnt/shared', '/mnt/shared/alice/work/run1'),
        '/mnt/shared/alice',
      );
    });

    test('takes the volume root when the user owns it', () {
      expect(anchor('/mnt/data', '/mnt/data/sub'), '/mnt/data');
    });

    test('skips owned folders the user cannot write', () {
      expect(
        anchor(
          '/mnt/shared',
          '/mnt/shared/alice/work/run1',
          readOnly: {'/mnt/shared/alice'},
        ),
        '/mnt/shared/alice/work',
      );
    });

    test('finds an owned folder below someone else\'s', () {
      expect(
        anchor('/mnt/shared', '/mnt/shared/bob/shared'),
        '/mnt/shared/bob/shared',
      );
    });

    test('gives up when no folder on the way is the user\'s', () {
      expect(anchor('/mnt/shared', '/mnt/shared/bob'), isNull);
      expect(anchor('/mnt/shared', '/mnt/shared/alice', uid: null), isNull);
      expect(anchor('/mnt/shared', '/srv/elsewhere'), isNull);
    });
  });

  group('prepareIn', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('waydir_cache_own_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String mode(String path) =>
        (FileStat.statSync(path).mode & 511).toRadixString(8);

    test('creates the cache folder readable by the owner only', () async {
      final dir = await GeneratorCacheLocation.prepareIn(tmp.path);

      expect(dir, p.join(tmp.path, '.waydir-cache', 'generator_cache'));
      expect(Directory(dir!).existsSync(), isTrue);
      expect(mode(p.join(tmp.path, '.waydir-cache')), '700');
    }, skip: Platform.isWindows);

    test('tightens an existing cache folder to 700', () async {
      final base = Directory(p.join(tmp.path, '.waydir-cache'))..createSync();
      await Process.run('chmod', ['755', base.path]);

      await GeneratorCacheLocation.prepareIn(tmp.path);

      expect(mode(base.path), '700');
    }, skip: Platform.isWindows);
  });

  test('cache folders recorded in the registry are found again', () async {
    final tmp = Directory.systemTemp.createTempSync('waydir_cache_reg_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fallback = p.join(tmp.path, 'support', 'generator_cache');
    final recorded = p.join(
      tmp.path,
      'disk',
      '.waydir-cache',
      'generator_cache',
    );
    Directory(recorded).createSync(recursive: true);
    File(p.join(tmp.path, 'support', GeneratorCacheLocation.registryName))
      ..createSync(recursive: true)
      ..writeAsStringSync('$recorded\n${p.join(tmp.path, 'gone')}\n');

    final dirs = await GeneratorCacheLocation.existingDirectories(
      fallback: fallback,
    );

    expect(dirs, contains(recorded));
    expect(dirs, isNot(contains(p.join(tmp.path, 'gone'))));
  });
}
