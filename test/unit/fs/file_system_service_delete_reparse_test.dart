import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/fs/file_system_service.dart';
import 'package:waydir/core/models/file_operation.dart';

void main() {
  test('deleteWorker removes a directory-reparse-point (e.g. a junction) '
      "without touching its target's real content", () async {
    if (!Platform.isWindows) return;

    final tmp = await Directory.systemTemp.createTemp('waydir_delete_');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final target = Directory('${tmp.path}\\target')..createSync();
    final targetFile = File('${target.path}\\file.txt')
      ..writeAsStringSync('keep me');
    final link = '${tmp.path}\\link';
    final mklink = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      link,
      target.path,
    ]);
    expect(mklink.exitCode, 0, reason: 'mklink /J failed: ${mklink.stderr}');

    final mainReceivePort = ReceivePort();
    final isolate = await Isolate.spawn(FileSystemService.deleteWorker, [
      mainReceivePort.sendPort,
    ]);
    addTearDown(isolate.kill);
    final events = StreamController<dynamic>.broadcast();
    mainReceivePort.listen(events.add);

    final workerSendPort = await events.stream.first as SendPort;
    workerSendPort.send(StartCommand(type: TaskType.delete, sources: [link]));
    await events.stream.firstWhere((m) => m is PreScanResultMessage);

    workerSendPort.send(ExecuteCommand(resolutions: const {}));
    final done =
        await events.stream.firstWhere((m) => m is TaskDoneMessage)
            as TaskDoneMessage;

    expect(done.errors, isEmpty);
    expect(Directory(link).existsSync(), isFalse);
    expect(
      targetFile.existsSync(),
      isTrue,
      reason: "deleting the junction must not touch the target's content",
    );
  });
}
