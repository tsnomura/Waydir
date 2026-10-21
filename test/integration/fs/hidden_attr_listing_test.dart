@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/fs/file_system_service.dart';
import 'package:waydir/core/fs/fs_worker_pool.dart';

void main() {
  test(
    'a Windows listing reports hidden and system attributes natively',
    () async {
      final dir = Directory.systemTemp.createTempSync('waydir_hidden_');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final name in ['plain.txt', 'hidden.txt', 'system.txt']) {
        File(p.join(dir.path, name)).writeAsStringSync(name);
      }
      Directory(p.join(dir.path, 'hidden_dir')).createSync();
      Process.runSync('attrib', ['+h', p.join(dir.path, 'hidden.txt')]);
      Process.runSync('attrib', ['+s', p.join(dir.path, 'system.txt')]);
      Process.runSync('attrib', ['+h', p.join(dir.path, 'hidden_dir')]);
      await FsWorkerPool.instance.ensureStarted();

      final entries = await FileSystemService.listDirectory(dir.path);
      final hidden = {for (final e in entries) e.name: e.hiddenAttr};

      expect(hidden, {
        'hidden_dir': true,
        'hidden.txt': true,
        'plain.txt': false,
        'system.txt': true,
      });
    },
    skip: Platform.isWindows ? false : 'Windows file attributes only',
  );
}
