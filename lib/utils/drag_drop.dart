import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../core/archive/archive_temp.dart';
import '../core/logging/app_logger.dart';

const formatLocalFile = CustomValueFormat<String>(
  applicationId: 'dev.waydir.local-file',
);

bool isVirtualDrop(DropSession session) =>
    session.items.isNotEmpty &&
    session.items.every(
      (i) =>
          i.localData == null &&
          !i.canProvide(Formats.fileUri) &&
          !i.canProvide(formatLocalFile),
    );

Future<List<String>> pathsFromSession(
  DropSession session, {
  void Function(int count)? onReceiving,
}) async {
  if (isVirtualDrop(session)) {
    return receiveVirtualFiles(session.items, onReceiving: onReceiving);
  }
  final paths = await _pathsFromSession(session);
  if (session.items.every((i) => i.localData != null)) return paths;

  return stageVolatileDropSources(paths);
}

Future<List<String>> receiveVirtualFiles(
  List<DropItem> items, {
  void Function(int count)? onReceiving,
}) async {
  final entries = <({DropItem item, String rel})>[];
  for (final item in items) {
    final name = await item.dataReader?.getSuggestedName();
    if (name == null) continue;
    final rel = p.posix.normalize(name.replaceAll('\\', '/'));
    if (rel.isEmpty ||
        rel == '.' ||
        p.posix.isAbsolute(rel) ||
        p.posix.split(rel).contains('..') ||
        rel.contains(':')) {
      continue;
    }
    entries.add((item: item, rel: rel));
  }
  if (entries.isEmpty) return const [];
  onReceiving?.call(entries.length);

  final stage = Directory(
    p.join(
      ArchiveTemp.stageRoot,
      'drop-${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  final folders = {
    for (final e in entries)
      if (entries.any((o) => o.rel.startsWith('${e.rel}/'))) e.rel,
  };
  final received = <String>{};
  for (final e in entries) {
    final dest = p.joinAll([stage.path, ...p.posix.split(e.rel)]);
    if (folders.contains(e.rel)) {
      Directory(dest).createSync(recursive: true);
      received.add(e.rel);
      continue;
    }
    Directory(p.dirname(dest)).createSync(recursive: true);
    try {
      final receiver = await e.item.dataReader?.getVirtualFileReceiver();
      if (receiver == null) continue;
      final (copied, _) = receiver.copyVirtualFile(targetFolder: stage.path);
      await copied;
      received.add(e.rel);
    } catch (err) {
      if (p.posix.extension(e.rel).isEmpty) {
        Directory(dest).createSync(recursive: true);
        received.add(e.rel);
      } else {
        log.warn('drop', 'could not receive dropped ${e.rel}', error: err);
      }
    }
  }

  final tops = {for (final rel in received) p.posix.split(rel).first};

  return [
    for (final top in tops)
      if (FileSystemEntity.typeSync(p.join(stage.path, top)) !=
          FileSystemEntityType.notFound)
        p.join(stage.path, top),
  ];
}

Future<List<String>> stageVolatileDropSources(List<String> paths) async {
  final temp = p.canonicalize(Directory.systemTemp.path);
  final stage = p.canonicalize(ArchiveTemp.stageRoot);
  final volatile = {
    for (final path in paths)
      if (p.isWithin(temp, p.canonicalize(path)) &&
          !p.isWithin(stage, p.canonicalize(path)))
        path,
  };
  if (volatile.isEmpty) return paths;
  final staging = Directory(
    p.join(
      ArchiveTemp.stageRoot,
      'drop-${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  final out = <String>[];
  for (final path in paths) {
    if (!volatile.contains(path)) {
      out.add(path);
      continue;
    }
    final dest = p.join(staging.path, p.basename(path));
    try {
      await _copyEntity(path, dest);
      out.add(dest);
    } on FileSystemException catch (e) {
      log.warn('drop', 'could not stage dropped $path', error: e);
    }
  }

  return out;
}

Future<void> _copyEntity(String source, String dest) async {
  final type = await FileSystemEntity.type(source, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await Directory(dest).create(recursive: true);
    await for (final child in Directory(source).list(followLinks: false)) {
      await _copyEntity(child.path, p.join(dest, p.basename(child.path)));
    }

    return;
  }
  if (type == FileSystemEntityType.file) {
    await File(source).copy(dest);
  }
}

Future<List<String>> _pathsFromSession(DropSession session) async {
  final paths = <String>[];
  for (final item in session.items) {
    final local = item.localData;
    if (local is Map && local['paths'] is List) {
      paths.addAll((local['paths'] as List).cast<String>());
      continue;
    }
    if (item.canProvide(formatLocalFile)) {
      final reader = item.dataReader;
      if (reader != null) {
        final completer = Completer<String?>();
        reader.getValue(formatLocalFile, (value) {
          completer.complete(value);
        }, onError: (_) => completer.complete(null));
        final data = await completer.future;
        if (data != null && data.isNotEmpty) {
          final lines = data.split('\n');
          for (final line in lines) {
            if (line.isNotEmpty) paths.add(line);
          }
          continue;
        }
      }
    }
    if (item.canProvide(Formats.fileUri)) {
      final reader = item.dataReader;
      if (reader != null) {
        final completer = Completer<String?>();
        reader.getValue(Formats.fileUri, (value) {
          completer.complete(value?.toFilePath());
        }, onError: (_) => completer.complete(null));
        final path = await completer.future;
        if (path != null && path.isNotEmpty) paths.add(path);
      }
    }
  }

  return paths;
}
