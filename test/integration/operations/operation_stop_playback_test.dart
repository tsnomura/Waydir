@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/models/file_operation.dart';
import 'package:waydir/core/platform/trash_location.dart';
import 'package:waydir/features/quick_look/generators/generator_page_controller.dart';
import 'package:waydir/features/quick_look/player/playback_registry.dart';
import 'package:waydir/features/quick_look/player/quick_look_playback_controller.dart';
import 'package:waydir/features/quick_look/player/quick_look_player.dart';
import 'package:waydir/features/operations/operation_store.dart';

import '../../support/ops.dart';

class _RecordingPlayer implements QuickLookPlayer {
  var stopCount = 0;

  @override
  Future<void> play(String path, double startSeconds) async {}

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

FileEntry _entry(String path) => FileEntry(
  name: p.basename(path),
  path: path,
  type: FileItemType.file,
  size: 1,
  modified: DateTime(2026),
);

void main() {
  group('OperationStore Quick Look playback release', () {
    late Directory tmpDir;
    late OperationStore store;
    late _RecordingPlayer player;
    late GeneratorPageController page;
    late QuickLookPlaybackController controller;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('waydir_ops_playback_');
      store = OperationStore();
      player = _RecordingPlayer();
      page = GeneratorPageController();
      controller = QuickLookPlaybackController(player: player);
      PlaybackRegistry.instance.register(controller);
    });

    tearDown(() {
      PlaybackRegistry.instance.unregister(controller);
      controller.dispose();
      page.dispose();
      store.dispose();
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('move stops playback of the source before moving it', () async {
      final src = p.join(tmpDir.path, 'song.mp3');
      File(src).writeAsStringSync('payload');
      final dest = Directory(p.join(tmpDir.path, 'out'))..createSync();
      controller.sync(_entry(src), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueMove([src], dest.path);
      final done = await waitForTask(
        store,
        (t) => t.type == TaskType.move && isTerminalTask(t),
      );

      expect(done.status, TaskStatus.completed);
      expect(done.errors, isEmpty);
      expect(player.stopCount, greaterThan(baseline));
      expect(File(p.join(dest.path, 'song.mp3')).existsSync(), isTrue);
      expect(File(src).existsSync(), isFalse);
    });

    test('move stops playback of the file being overwritten', () async {
      final src = p.join(tmpDir.path, 'in', 'song.mp3');
      File(src)
        ..createSync(recursive: true)
        ..writeAsStringSync('new');
      final dest = Directory(p.join(tmpDir.path, 'out'))..createSync();
      final target = File(p.join(dest.path, 'song.mp3'))
        ..writeAsStringSync('old');
      controller.sync(_entry(target.path), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueMove([src], dest.path);
      final waiting = await waitForTask(
        store,
        (t) =>
            t.type == TaskType.move && t.status == TaskStatus.waitingConflicts,
      );
      store.resolveCurrentConflict(waiting.id, ConflictResolution.overwrite);
      final done = await waitForTask(
        store,
        (t) => t.type == TaskType.move && isTerminalTask(t),
      );

      expect(done.status, TaskStatus.completed);
      expect(player.stopCount, greaterThan(baseline));
      expect(target.readAsStringSync(), 'new');
    });

    test('delete stops playback of the source', () async {
      final src = p.join(tmpDir.path, 'song.mp3');
      File(src).writeAsStringSync('payload');
      controller.sync(_entry(src), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueDelete([src]);
      final done = await waitForTask(
        store,
        (t) => t.type == TaskType.delete && isTerminalTask(t),
      );

      expect(done.status, TaskStatus.completed);
      expect(player.stopCount, greaterThan(baseline));
      expect(File(src).existsSync(), isFalse);
    });

    test('trash stops playback of the source', () async {
      final src = p.join(tmpDir.path, 'missing', 'song.mp3');
      controller.sync(_entry(src), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueTrash([src]);
      await waitForTask(
        store,
        (t) => t.type == TaskType.trash && isTerminalTask(t),
      );

      expect(player.stopCount, greaterThan(baseline));
    });

    test(
      'trashRestore stops playback of the trashed data and the restore target',
      () async {
        final dataPath = p.join(tmpDir.path, 'trashdata', 'song.mp3');
        final originalPath = p.join(tmpDir.path, 'restored', 'song.mp3');
        File(originalPath).createSync(recursive: true);
        final dataPlayer = _RecordingPlayer();
        final dataController = QuickLookPlaybackController(player: dataPlayer);
        PlaybackRegistry.instance.register(dataController);
        controller.sync(_entry(originalPath), page, blocked: false);
        dataController.sync(_entry(dataPath), page, blocked: false);
        final baseline = player.stopCount;
        final dataBaseline = dataPlayer.stopCount;

        store.enqueueTrashRestore([
          TrashEntry(
            virtualPath: '::trash/song.mp3',
            displayName: 'song.mp3',
            realDataPath: dataPath,
            originalPath: originalPath,
            deletedAt: DateTime(2026),
            size: 1,
            isDirectory: false,
          ),
        ]);
        await waitForTask(
          store,
          (t) => t.type == TaskType.trashRestore && isTerminalTask(t),
        );

        expect(player.stopCount, greaterThan(baseline));
        expect(dataPlayer.stopCount, greaterThan(dataBaseline));
        PlaybackRegistry.instance.unregister(dataController);
        dataController.dispose();
      },
    );

    test('copy keeps playing the source', () async {
      final src = p.join(tmpDir.path, 'song.mp3');
      File(src).writeAsStringSync('payload');
      final dest = Directory(p.join(tmpDir.path, 'out'))..createSync();
      controller.sync(_entry(src), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueCopy([src], dest.path);
      final done = await waitForTask(
        store,
        (t) => t.type == TaskType.copy && isTerminalTask(t),
      );

      expect(done.status, TaskStatus.completed);
      expect(player.stopCount, baseline);
      expect(File(p.join(dest.path, 'song.mp3')).existsSync(), isTrue);
    });

    test('move does not stop playback of an unrelated file', () async {
      final src = p.join(tmpDir.path, 'a.mp3');
      final shown = p.join(tmpDir.path, 'b.mp3');
      File(src).writeAsStringSync('payload');
      File(shown).writeAsStringSync('payload');
      final dest = Directory(p.join(tmpDir.path, 'out'))..createSync();
      controller.sync(_entry(shown), page, blocked: false);
      final baseline = player.stopCount;

      store.enqueueMove([src], dest.path);
      final done = await waitForTask(
        store,
        (t) => t.type == TaskType.move && isTerminalTask(t),
      );

      expect(done.status, TaskStatus.completed);
      expect(player.stopCount, baseline);
    });
  });
}
