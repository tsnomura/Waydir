import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/fs/file_system_service.dart';
import 'package:waydir/core/models/file_operation.dart';

class _CopyRun {
  final Isolate isolate;
  final Stream<dynamic> events;
  final SendPort workerSendPort;

  const _CopyRun(this.isolate, this.events, this.workerSendPort);

  static Future<_CopyRun> start() async {
    final mainReceivePort = ReceivePort();
    final isolate = await Isolate.spawn(FileSystemService.copyWorker, [
      mainReceivePort.sendPort,
    ]);
    final events = StreamController<dynamic>.broadcast();
    mainReceivePort.listen(events.add);
    final workerSendPort = await events.stream.first as SendPort;

    return _CopyRun(isolate, events.stream, workerSendPort);
  }

  Future<PreScanResultMessage> scan(
    List<String> sources,
    String destination,
  ) async {
    workerSendPort.send(
      StartCommand(
        type: TaskType.copy,
        sources: sources,
        destination: destination,
      ),
    );

    return await events.firstWhere((m) => m is PreScanResultMessage)
        as PreScanResultMessage;
  }

  Future<TaskDoneMessage> execute([
    Map<String, ConflictResolution> resolutions = const {},
  ]) async {
    workerSendPort.send(ExecuteCommand(resolutions: resolutions));

    return await events.firstWhere((m) => m is TaskDoneMessage)
        as TaskDoneMessage;
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('waydir_copy_');
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('copies nested files and directories with correct totals, no conflicts '
      'against a destination that does not exist yet', () async {
    final src = Directory('${tmp.path}\\src')..createSync();
    File('${src.path}\\a.txt').writeAsStringSync('A');
    final sub = Directory('${src.path}\\sub')..createSync();
    File('${sub.path}\\b.txt').writeAsStringSync('BB');
    final dst = '${tmp.path}\\dst';

    final run = await _CopyRun.start();
    addTearDown(run.isolate.kill);

    final preScan = await run.scan([src.path], dst);
    expect(preScan.totalFiles, 4); // src, sub, a.txt, sub/b.txt
    expect(preScan.totalBytes, 3); // 'A' + 'BB'
    expect(preScan.conflicts, isEmpty);

    final done = await run.execute();
    expect(done.errors, isEmpty);
    expect(File('$dst\\src\\a.txt').readAsStringSync(), 'A');
    expect(File('$dst\\src\\sub\\b.txt').readAsStringSync(), 'BB');
  });

  test('detects a conflict against an existing destination file and overwrites '
      'it once resolved', () async {
    final src = Directory('${tmp.path}\\src')..createSync();
    final srcFile = File('${src.path}\\file.txt')
      ..writeAsStringSync('new content');
    final dst = '${tmp.path}\\dst';
    final existingDir = Directory('$dst\\src')..createSync(recursive: true);
    File('${existingDir.path}\\file.txt').writeAsStringSync('old content');

    final run = await _CopyRun.start();
    addTearDown(run.isolate.kill);

    final preScan = await run.scan([src.path], dst);
    expect(preScan.conflicts, hasLength(1));
    expect(preScan.conflicts.first.sourcePath, srcFile.path);

    final done = await run.execute({
      srcFile.path: ConflictResolution.overwrite,
    });
    expect(done.errors, isEmpty);
    expect(File('$dst\\src\\file.txt').readAsStringSync(), 'new content');
  });

  test('deep-copies a file symlink instead of recreating it as a reparse '
      'point (regression: File.copy() does not follow reparse points, so '
      "forcing the async-copy path here throws PathNotFoundException even "
      'though the source genuinely resolves)', () async {
    if (!Platform.isWindows) return;

    final src = Directory('${tmp.path}\\src')..createSync();
    final real = File('${src.path}\\real.txt')
      ..writeAsStringSync('deep content');
    Link('${src.path}\\alias.txt').createSync(real.path);
    final dst = '${tmp.path}\\dst';

    final run = await _CopyRun.start();
    addTearDown(run.isolate.kill);

    await run.scan([src.path], dst);
    final done = await run.execute();
    expect(done.errors, isEmpty);

    final copiedLink = '$dst\\src\\alias.txt';
    expect(
      FileSystemEntity.typeSync(copiedLink, followLinks: false),
      FileSystemEntityType.file,
      reason: 'the copy should be a real file, not a reparse point',
    );
    expect(File(copiedLink).readAsStringSync(), 'deep content');
  });

  test('deep-copies through a directory junction instead of recreating it as '
      'a reparse point', () async {
    if (!Platform.isWindows) return;

    final target = Directory('${tmp.path}\\target')..createSync();
    File('${target.path}\\inside.txt').writeAsStringSync('deep content');
    final src = Directory('${tmp.path}\\src')..createSync();
    final linkPath = '${src.path}\\linked';
    final mklink = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      linkPath,
      target.path,
    ]);
    expect(mklink.exitCode, 0, reason: 'mklink /J failed: ${mklink.stderr}');
    final dst = '${tmp.path}\\dst';

    final run = await _CopyRun.start();
    addTearDown(run.isolate.kill);

    await run.scan([src.path], dst);
    final done = await run.execute();
    expect(done.errors, isEmpty);

    final copiedLink = '$dst\\src\\linked';
    expect(
      FileSystemEntity.typeSync(copiedLink, followLinks: false),
      FileSystemEntityType.directory,
      reason: 'the copy should be a real directory, not a reparse point',
    );
    expect(File('$copiedLink\\inside.txt').readAsStringSync(), 'deep content');
  });
}
