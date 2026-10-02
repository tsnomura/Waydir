import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/fs/sftp_session_manager.dart';
import '../../core/fs/waydir_core_loader.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/app_dirs.dart';
import '../../utils/concurrency_gate.dart';

const _maxBytes = 20 * 1024 * 1024;
const _chunkBytes = 1024 * 1024;

class RemoteThumbnailCache {
  RemoteThumbnailCache._();

  static final _gate = ConcurrencyGate(2);
  static final _inFlight = <String, Future<String?>>{};
  static final _failedKeys = <String>{};

  static Future<String?> fetch(FileEntry entry) {
    if (entry.size <= 0 || entry.size > _maxBytes) return Future.value(null);
    final key = sha256
        .convert(
          utf8.encode('${entry.realPath}|${entry.modifiedMs}|${entry.size}'),
        )
        .toString();
    if (_failedKeys.contains(key)) return Future.value(null);

    return _inFlight.putIfAbsent(key, () async {
      try {
        final path = await _download(entry, key);
        if (path == null) _failedKeys.add(key);

        return path;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static Future<String?> _download(FileEntry entry, String key) async {
    final dir = await AppDirs.generatorCache();
    final ext = entry.extension.isEmpty ? 'bin' : entry.extension;
    final target = p.join(dir, 'remote-$key.$ext');
    if (await File(target).exists()) return target;
    final record = SftpSessionManager.recordFor(entry.realPath);
    if (record == null) return null;
    final remote = SftpSessionManager.remotePath(entry.realPath);
    final tmp = p.join(dir, 'tmp-remote-$key.$ext');

    await _gate.acquire();
    try {
      final ok = await _downloadInIsolate(
        record.sessionId,
        remote,
        entry.size,
        tmp,
      );
      if (!ok) {
        await _tryDelete(tmp);

        return null;
      }
      await File(tmp).rename(target);

      return target;
    } catch (error, stack) {
      log.warn(
        'thumbnails',
        'remote thumbnail download failed for ${entry.realPath}',
        error: error,
        stack: stack,
      );
      await _tryDelete(tmp);

      return null;
    } finally {
      _gate.release();
    }
  }

  static Future<void> _tryDelete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}

Future<bool> _downloadInIsolate(
  int sessionId,
  String remote,
  int size,
  String tmpPath,
) => Isolate.run(() => _downloadChunks(sessionId, remote, size, tmpPath));

bool _downloadChunks(int sessionId, String remote, int size, String tmpPath) {
  final out = File(tmpPath).openSync(mode: FileMode.write);
  try {
    var offset = 0;
    while (offset < size) {
      final remaining = size - offset;
      final length = remaining < _chunkBytes ? remaining : _chunkBytes;
      final chunk = WaydirCoreLoader.sftpRead(
        sessionId,
        remote,
        start: offset,
        length: length,
      );
      if (chunk == null || chunk.isEmpty) return false;
      out.writeFromSync(chunk);
      offset += chunk.length;
    }

    return true;
  } finally {
    out.closeSync();
  }
}
