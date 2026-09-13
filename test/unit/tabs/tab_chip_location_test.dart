import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/platform/platform_paths.dart';
import 'package:waydir/features/drives/drive_model.dart';
import 'package:waydir/features/drives/drive_store.dart';
import 'package:waydir/features/tabs/tab_chip.dart';

void main() {
  setUp(() {
    driveStore.drives.value = [];
  });

  tearDown(() {
    driveStore.drives.value = [];
    PlatformPaths.isWindowsOverrideForTesting = null;
  });

  group('classifyTabLocation', () {
    test('an sftp:// path is its own sftp kind', () {
      expect(
        classifyTabLocation('sftp://user@host/remote/folder'),
        TabLocationKind.sftp,
      );
    });

    test('an smb:// path is always network', () {
      expect(
        classifyTabLocation('smb://server/share/folder'),
        TabLocationKind.network,
      );
    });

    test('a Windows UNC path is network even with no matching drive', () {
      PlatformPaths.isWindowsOverrideForTesting = true;
      expect(
        classifyTabLocation(r'\\server\share\folder'),
        TabLocationKind.network,
      );
    });

    test('a path under a removable drive is removable', () {
      if (!Platform.isWindows) return;
      driveStore.drives.value = [
        const Drive(
          id: 'E:\\',
          label: 'USB',
          mountPoint: 'E:\\',
          isRemovable: true,
        ),
      ];
      expect(classifyTabLocation(r'E:\photos'), TabLocationKind.removable);
    });

    test('a path under a network drive is network', () {
      if (!Platform.isWindows) return;
      driveStore.drives.value = [
        const Drive(
          id: 'Z:\\',
          label: 'Shared',
          mountPoint: 'Z:\\',
          isRemovable: false,
          isNetwork: true,
        ),
      ];
      expect(classifyTabLocation(r'Z:\shared\docs'), TabLocationKind.network);
    });

    test('a path under a fixed local drive is local', () {
      if (!Platform.isWindows) return;
      driveStore.drives.value = [
        const Drive(
          id: 'C:\\',
          label: 'Local Disk',
          mountPoint: 'C:\\',
          isRemovable: false,
        ),
      ];
      expect(classifyTabLocation(r'C:\Users\me'), TabLocationKind.local);
    });

    test('a path matching no known drive falls back to local', () {
      expect(classifyTabLocation('/home/me/docs'), TabLocationKind.local);
    });
  });

  group('tabDriveLetter', () {
    test('extracts the drive letter on Windows', () {
      PlatformPaths.isWindowsOverrideForTesting = true;
      expect(tabDriveLetter(r'C:\Users\me'), 'C');
      expect(tabDriveLetter(r'x:\project'), 'X');
    });

    test('returns null for a remote URI', () {
      PlatformPaths.isWindowsOverrideForTesting = true;
      expect(tabDriveLetter('sftp://user@host/remote'), isNull);
    });

    test('returns null off Windows', () {
      PlatformPaths.isWindowsOverrideForTesting = false;
      expect(tabDriveLetter(r'C:\Users\me'), isNull);
    });
  });
}
