@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_temp.dart';
import 'package:waydir/utils/drag_drop.dart';

void main() {
  test(
    'drops from the temp folder are staged before the source vanishes',
    () async {
      final source = Directory.systemTemp.createTempSync('7zE_test');
      File(p.join(source.path, 'doc.pdf')).writeAsStringSync('pdf');
      Directory(p.join(source.path, 'sub')).createSync();
      File(p.join(source.path, 'sub', 'x.txt')).writeAsStringSync('x');
      final keep = Directory(p.join(Directory.current.path, 'pubspec.yaml'));

      final staged = await stageVolatileDropSources([
        p.join(source.path, 'doc.pdf'),
        p.join(source.path, 'sub'),
        keep.path,
      ]);
      source.deleteSync(recursive: true);

      expect(p.isWithin(ArchiveTemp.stageRoot, staged[0]), isTrue);
      expect(File(staged[0]).readAsStringSync(), 'pdf');
      expect(File(p.join(staged[1], 'x.txt')).readAsStringSync(), 'x');
      expect(staged[2], keep.path);
      ArchiveTemp.endSession();
    },
  );
}
