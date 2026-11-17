import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/drives/drive_service.dart';
import 'package:waydir/features/drives/unix_statvfs.dart';

const _lsblk = '''
{"blockdevices": [
  {"name": "sdb", "type": "disk", "mountpoint": null, "size": "1G",
   "label": null, "rm": true, "fstype": null, "parttypename": null,
   "children": [
     {"name": "sdb1", "type": "part", "mountpoint": "/tmp", "size": "1G",
      "label": "STICK", "rm": true, "fstype": "vfat", "parttypename": null}
   ]}
]}
''';

void main() {
  group('statvfsSpace', () {
    test('matches df for the root filesystem', () async {
      final space = statvfsSpace('/');
      expect(space, isNotNull);
      final df = await Process.run('df', ['-Pk', '/']);
      final parts = (df.stdout as String)
          .trim()
          .split('\n')
          .last
          .split(RegExp(r'\s+'));
      expect(space!.totalBytes, int.parse(parts[1]) * 1024);
      expect(
        (space.freeBytes - int.parse(parts[3]) * 1024).abs(),
        lessThan(64 * 1024 * 1024),
      );
    }, skip: !Platform.isLinux);

    test('returns null for a missing path', () {
      expect(statvfsSpace('/no/such/path/for/waydir'), isNull);
    }, skip: !Platform.isLinux);
  });

  group('linux drive probe', () {
    late int lsblkCalls;
    late String signature;
    late DriveService service;

    setUp(() {
      lsblkCalls = 0;
      signature = 'a';
      service = linuxDriveServiceForTesting(
        lsblk: () async {
          lsblkCalls++;

          return _lsblk;
        },
        signature: () async => signature,
      );
    });

    test(
      'reuses lsblk output while mounts and devices are unchanged',
      () async {
        final first = await service.getDrives();
        final second = await service.getDrives();
        final third = await service.getDrives();

        expect(lsblkCalls, 1);
        expect(first.map((d) => d.id), ['/', '/dev/sdb1']);
        expect(second.map((d) => d.id), ['/', '/dev/sdb1']);
        expect(third.map((d) => d.id), ['/', '/dev/sdb1']);
        expect(third.last.label, 'STICK');
      },
    );

    test('runs lsblk again when the mount signature changes', () async {
      await service.getDrives();
      signature = 'b';
      await service.getDrives();

      expect(lsblkCalls, 2);
    });

    test('runs lsblk again after enough cached polls', () async {
      for (var i = 0; i < 22; i++) {
        await service.getDrives();
      }

      expect(lsblkCalls, 2);
    });

    test('never caches when the signature cannot be read', () async {
      service = linuxDriveServiceForTesting(
        lsblk: () async {
          lsblkCalls++;

          return _lsblk;
        },
        signature: () async => null,
      );
      await service.getDrives();
      await service.getDrives();

      expect(lsblkCalls, 2);
    });
  });
}
