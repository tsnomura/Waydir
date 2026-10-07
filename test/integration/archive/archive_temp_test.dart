@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_temp.dart';

void main() {
  test('session start removes abandoned folders and end removes its own', () {
    final stageBase = p.dirname(ArchiveTemp.stageRoot);
    final openBase = p.dirname(ArchiveTemp.openRoot);
    final legacy = Directory(p.join(stageBase, 'legacy-test'))
      ..createSync(recursive: true);
    final dead = Directory(p.join(stageBase, '999999991'))
      ..createSync(recursive: true);
    File(p.join(dead.path, '.session.lock')).writeAsStringSync('');
    final deadOpen = Directory(p.join(openBase, '999999991'))
      ..createSync(recursive: true);

    ArchiveTemp.startSession();
    expect(legacy.existsSync(), isFalse);
    expect(dead.existsSync(), isFalse);
    expect(deadOpen.existsSync(), isFalse);

    File(p.join(ArchiveTemp.stageRoot, 'staged.txt')).writeAsStringSync('x');
    Directory(ArchiveTemp.openRoot).createSync(recursive: true);
    File(p.join(ArchiveTemp.openRoot, 'opened.txt')).writeAsStringSync('x');

    ArchiveTemp.endSession();
    expect(Directory(ArchiveTemp.stageRoot).existsSync(), isFalse);
    expect(Directory(ArchiveTemp.openRoot).existsSync(), isFalse);
  });
}
