import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_temp.dart';
import 'package:waydir/features/operations/operation_store.dart';

void main() {
  test('dropStagingDirs picks only drop staging folders of the sources', () {
    final root = p.canonicalize(ArchiveTemp.stageRoot);
    final drop = p.join(root, 'drop-123');

    final dirs = OperationStore.dropStagingDirs([
      p.join(drop, 'IMG_0747.HEIC'),
      p.join(drop, 'DCIM', '100APPLE'),
      p.join(root, 'tree-1', 'a.txt'),
      p.join(Directory.systemTemp.path, 'elsewhere.txt'),
      r'C:\Users\someone\photo.jpg',
    ]);

    expect(dirs, {drop});
  });

  test('dropStagingDirs ignores sources outside the staging root', () {
    expect(
      OperationStore.dropStagingDirs([
        p.join(Directory.systemTemp.path, 'drop-1', 'x.jpg'),
      ]),
      isEmpty,
    );
  });
}
