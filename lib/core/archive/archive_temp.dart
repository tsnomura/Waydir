import 'dart:io';

import 'package:path/path.dart' as p;

import '../logging/app_logger.dart';

class ArchiveTemp {
  ArchiveTemp._();

  static const _lockName = '.session.lock';

  static String get _stageBase =>
      p.join(Directory.systemTemp.path, 'waydir-archive-stage');

  static String get _openBase =>
      p.join(Directory.systemTemp.path, 'waydir-archive');

  static String get _session => '$pid';

  static String get stageRoot => p.join(_stageBase, _session);

  static String get openRoot => p.join(_openBase, _session);

  static RandomAccessFile? _lock;

  static void startSession() {
    try {
      Directory(stageRoot).createSync(recursive: true);
      _lock = File(p.join(stageRoot, _lockName)).openSync(mode: FileMode.write)
        ..lockSync();
    } on FileSystemException catch (e) {
      log.warn('archive', 'could not lock archive temp session', error: e);
    }
    _removeAbandonedSessions();
  }

  static void endSession() {
    try {
      _lock?.unlockSync();
      _lock?.closeSync();
    } on FileSystemException catch (_) {}
    _lock = null;
    _delete(Directory(stageRoot));
    _delete(Directory(openRoot));
  }

  static void _removeAbandonedSessions() {
    for (final base in [_stageBase, _openBase]) {
      final dir = Directory(base);
      if (!dir.existsSync()) continue;
      for (final child in dir.listSync(followLinks: false)) {
        final name = p.basename(child.path);
        if (name == _session || _isLive(name)) continue;
        _delete(child);
      }
    }
  }

  static bool _isLive(String session) {
    if (int.tryParse(session) == null) return false;
    final lock = File(p.join(_stageBase, session, _lockName));
    if (!lock.existsSync()) return false;
    RandomAccessFile? raf;
    try {
      raf = lock.openSync(mode: FileMode.append);
      raf.lockSync(FileLock.exclusive);
      raf.unlockSync();

      return false;
    } on FileSystemException catch (_) {
      return true;
    } finally {
      try {
        raf?.closeSync();
      } on FileSystemException catch (_) {}
    }
  }

  static void _delete(FileSystemEntity entity) {
    if (!entity.existsSync()) return;
    try {
      entity.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      log.warn('archive', 'could not remove ${entity.path}', error: e);
    }
  }
}
