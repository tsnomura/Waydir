import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/code_editor.dart';
import 'package:waydir/features/quick_look/quick_look_reload.dart';

void main() {
  group('FileChangeWatcher', () {
    const interval = Duration(milliseconds: 25);

    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('waydir_reload_test');
      file = File('${dir.path}${Platform.pathSeparator}a.txt');
      file.writeAsStringSync('v1');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<void> settle([int ms = 150]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('does not report while the file is unchanged', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      expect(changes, isEmpty);
      watcher.stop();
    });

    test('reports a changed file exactly once with the new stats', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(changes, hasLength(1));
      final stat = file.statSync();
      expect(changes.single, [stat.modified.millisecondsSinceEpoch, stat.size]);
      await settle();
      expect(changes, hasLength(1));
      watcher.stop();
    });

    test('reports each consecutive change once', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(changes, hasLength(1));
      file.writeAsStringSync('v3');
      await settle();
      expect(changes, hasLength(2));
      final stat = file.statSync();
      expect(changes.last, [stat.modified.millisecondsSinceEpoch, stat.size]);
      watcher.stop();
    });

    test('reports an mtime-only change', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      final original = file.statSync();
      final newModified = original.modified.add(const Duration(seconds: 5));
      file.setLastModifiedSync(newModified);
      await settle();
      expect(changes, hasLength(1));
      expect(changes.single, [
        newModified.millisecondsSinceEpoch,
        original.size,
      ]);
      watcher.stop();
    });

    test('stop disables reporting', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      watcher.stop();
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(changes, isEmpty);
    });

    test(
      'restarting with the same path keeps the baseline and timer',
      () async {
        final changes = <List<int>>[];
        final watcher = FileChangeWatcher(
          interval: interval,
          onChanged: (path, modifiedMs, size) =>
              changes.add([modifiedMs, size]),
        );
        watcher.start(file.path);
        await settle();
        watcher.start(file.path);
        await settle(200);
        expect(changes, isEmpty);
        file.writeAsStringSync('v2-a-lot-longer');
        await settle();
        expect(changes, hasLength(1));
        watcher.stop();
      },
    );

    test('switching to another path stops reporting the old one', () async {
      final other = File('${dir.path}${Platform.pathSeparator}b.txt');
      other.writeAsStringSync('w1');
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(changes, hasLength(1));
      watcher.start(other.path);
      await settle();
      file.writeAsStringSync('v3-even-longer-content');
      await settle();
      expect(changes, hasLength(1));
      other.writeAsStringSync('w2-a-lot-longer-content');
      await settle();
      expect(changes, hasLength(2));
      expect(changes.last[0], other.statSync().modified.millisecondsSinceEpoch);
      watcher.stop();
    });

    test(
      'tolerates the file being deleted and reports its recreation',
      () async {
        final changes = <List<int>>[];
        final watcher = FileChangeWatcher(
          interval: interval,
          onChanged: (path, modifiedMs, size) =>
              changes.add([modifiedMs, size]),
        );
        watcher.start(file.path);
        await settle();
        file.deleteSync();
        await settle();
        expect(changes, isEmpty);
        file.writeAsStringSync('recreated-with-more-content');
        await settle();
        expect(changes, hasLength(1));
        watcher.stop();
      },
    );

    test('a write between suspend and resume is not reported', () async {
      final changes = <List<int>>[];
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => changes.add([modifiedMs, size]),
      );
      watcher.start(file.path);
      await settle();
      watcher.suspend();
      file.writeAsStringSync('v2-saved-by-the-editor');
      await settle();
      expect(changes, isEmpty);
      final stat = await watcher.resume();
      expect(stat?.size, file.statSync().size);
      await settle();
      expect(changes, isEmpty);
      file.writeAsStringSync('v3-changed-elsewhere-afterwards');
      await settle();
      expect(changes, hasLength(1));
      watcher.stop();
    });

    test('resume is a no-op when not watching', () async {
      final watcher = FileChangeWatcher(
        interval: interval,
        onChanged: (path, modifiedMs, size) => fail('should not fire'),
      );
      watcher.suspend();
      expect(await watcher.resume(), isNull);
      watcher.stop();
    });
  });

  group('QuickLookReloadController', () {
    const interval = Duration(milliseconds: 25);

    late Directory dir;
    late File file;
    late FileEntry entry;
    late CodeEditorController editor;
    late QuickLookReloadController reload;
    late int skipped;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dir = await Directory.systemTemp.createTemp('waydir_reload_ctrl_test');
      file = File('${dir.path}${Platform.pathSeparator}a.txt');
      file.writeAsStringSync('v1');
      final stat = file.statSync();
      entry = FileEntry.raw(
        name: 'a.txt',
        path: file.path,
        type: FileItemType.file,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
      skipped = 0;
      editor = CodeEditorController();
      reload = QuickLookReloadController(
        editorController: editor,
        onReloadSkipped: () => skipped++,
        interval: interval,
      );
    });

    tearDown(() async {
      reload.dispose();
      editor.dispose();
      await dir.delete(recursive: true);
    });

    Future<void> settle([int ms = 150]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    test('an outside change bumps the generation and fresh stats', () async {
      reload.watch(entry);
      await settle();
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(reload.generation, 1);
      expect(reload.shown(entry)!.size, file.statSync().size);
    });

    test('a guarded editor write neither reloads nor reports', () async {
      reload.watch(entry);
      await settle();
      await editor.writeGuard!(() async {
        file.writeAsStringSync('v2-saved-by-the-editor');
        await settle();
      });
      await settle();
      expect(reload.generation, 0);
      expect(skipped, 0);
      expect(reload.shown(entry)!.size, file.statSync().size);
    });

    test('an outside change while dirty is reported as skipped', () async {
      reload.watch(entry);
      await settle();
      editor.dirty.value = true;
      file.writeAsStringSync('v2-a-lot-longer');
      await settle();
      expect(reload.generation, 0);
      expect(skipped, 1);
    });

    test('folders and remote paths are not watched', () {
      final folder = FileEntry.raw(
        name: 'd',
        path: dir.path,
        type: FileItemType.folder,
        size: 0,
        modifiedMs: 0,
      );
      expect(QuickLookReloadController.canReload(folder), isFalse);
      expect(QuickLookReloadController.canReload(entry), isTrue);
      expect(QuickLookReloadController.canReload(null), isFalse);
    });
  });

  group('FileEntry.copyWithStats', () {
    FileEntry base() => FileEntry.raw(
      name: 'notes.txt',
      path: r'C:\docs\notes.txt',
      type: FileItemType.file,
      size: 10,
      modifiedMs: 100,
      createdMs: 50,
      addedMs: 60,
      mode: 438,
      uid: 7,
      gid: 8,
      hiddenAttr: true,
    );

    test('returns the same instance when stats are unchanged', () {
      final entry = base();
      expect(
        identical(entry.copyWithStats(size: 10, modifiedMs: 100), entry),
        isTrue,
      );
    });

    test('updates stats and keeps every other field', () {
      final entry = base();
      final copy = entry.copyWithStats(size: 42, modifiedMs: 200);
      expect(copy, isNot(same(entry)));
      expect(copy.size, 42);
      expect(copy.modifiedMs, 200);
      expect(copy.name, entry.name);
      expect(copy.path, entry.path);
      expect(copy.type, entry.type);
      expect(copy.createdMs, 50);
      expect(copy.addedMs, 60);
      expect(copy.mode, 438);
      expect(copy.uid, 7);
      expect(copy.gid, 8);
      expect(copy.hiddenAttr, isTrue);
    });

    test('falls back to path for realPath when the original has none', () {
      final copy = base().copyWithStats(size: 42, modifiedMs: 200);
      expect(copy.realPath, r'C:\docs\notes.txt');
    });

    test('keeps an explicit realPath and ghostOf', () {
      final real = base();
      final ghost = FileEntry.raw(
        name: 'notes.txt',
        path: 'trash://notes.txt',
        type: FileItemType.file,
        size: 10,
        modifiedMs: 100,
        realPath: real.path,
        ghostOf: real,
      );
      final copy = ghost.copyWithStats(size: 42, modifiedMs: 200);
      expect(copy.realPath, real.path);
      expect(copy.ghostOf, same(real));
      expect(copy.path, 'trash://notes.txt');
    });
  });

  group('evictPreviewImage', () {
    test('does not throw for an existing file', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = Directory.systemTemp.createTempSync('waydir_reload_test');
      final file = File('${dir.path}${Platform.pathSeparator}x.png');
      file.writeAsBytesSync(List.filled(16, 0));
      addTearDown(() => dir.deleteSync(recursive: true));
      evictPreviewImage(file.path);
    });
  });
}
