@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/fs/file_system_service.dart';
import 'package:waydir/core/models/file_operation.dart';
import 'package:waydir/features/operations/operation_store.dart';

void main() {
  late Directory tmp;
  late String zipPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('waydir_arcbrowse');
    final archive = Archive()
      ..addFile(ArchiveFile.string('top.txt', 'top'))
      ..addFile(ArchiveFile.string('a/one.txt', 'one'))
      ..addFile(ArchiveFile.string('a/b/two.txt', 'two'))
      ..addFile(ArchiveFile.string('a/b/c/three.txt', 'three'));
    zipPath = p.join(tmp.path, 'sample.zip');
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<List<String>> names(String path) async =>
      (await FileSystemService.listDirectory(path)).map((e) => e.name).toList()
        ..sort();

  test('lists every level of a nested archive', () async {
    expect(await names(zipPath), ['a', 'top.txt']);
    expect(await names(p.join(zipPath, 'a')), ['b', 'one.txt']);
    expect(await names(p.join(zipPath, 'a', 'b')), ['c', 'two.txt']);
    expect(await names(p.join(zipPath, 'a', 'b', 'c')), ['three.txt']);
  });

  test('copying nested archive entries through the operation queue', () async {
    final dest = Directory(p.join(tmp.path, 'dest'))..createSync();
    final ops = OperationStore();
    addTearDown(ops.dispose);

    ops.enqueueCopy([
      p.join(zipPath, 'a', 'b'),
      p.join(zipPath, 'top.txt'),
    ], dest.path);
    expect(ops.tasks.value.map((t) => t.type).toList(), [TaskType.plugin]);
    for (var i = 0; i < 200; i++) {
      final list = ops.tasks.value;
      if (list.isNotEmpty &&
          list.every((t) => t.type != TaskType.plugin) &&
          list.every(
            (t) =>
                t.status == TaskStatus.completed ||
                t.status == TaskStatus.failed ||
                t.status == TaskStatus.cancelled,
          )) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(ops.tasks.value.map((t) => t.status).toList(), [
      TaskStatus.completed,
    ]);
    expect(File(p.join(dest.path, 'top.txt')).readAsStringSync(), 'top');
    expect(File(p.join(dest.path, 'b', 'two.txt')).readAsStringSync(), 'two');
    expect(File(p.join(dest.path, 'b', 'c', 'three.txt')).existsSync(), isTrue);
  });

  test('materializes nested archive entries for copying', () async {
    final staged = await FileSystemService.materializeArchiveSources([
      p.join(zipPath, 'a', 'b'),
      p.join(zipPath, 'a', 'b', 'two.txt'),
    ]);

    expect(File(p.join(staged[0], 'two.txt')).readAsStringSync(), 'two');
    expect(File(p.join(staged[0], 'c', 'three.txt')).existsSync(), isTrue);
    expect(File(staged[1]).readAsStringSync(), 'two');
  });
}
