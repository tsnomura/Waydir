import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../../../core/models/file_entry.dart';

/// Whether [entry] has at least one audio stream, via a cheap `ffprobe`
/// check — playback should stay off for a muted video (it still gets the
/// usual still-frame page browsing, just no sound to play). Hardcodes
/// `ffprobe` rather than going through a configured generator's own probe
/// command: this is an internal yes/no gate for Quick Look's playback
/// decision, not a user-configurable preview.
///
/// Fails closed: a missing `ffprobe`, a timeout, or any other error is
/// treated the same as "no audio" — playback simply stays off, it never
/// blocks the rest of Quick Look.
class AudioStreamProbe {
  AudioStreamProbe._();

  static const _timeout = Duration(seconds: 5);

  static final _cache = <String, bool>{};
  static final _inFlight = <String, Future<bool>>{};

  static Future<bool> hasAudio(FileEntry entry) {
    final key = '${entry.realPath}|${entry.modifiedMs}|${entry.size}';
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    return _inFlight.putIfAbsent(key, () async {
      try {
        return await _probe(entry, key);
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static Future<bool> _probe(FileEntry entry, String key) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-select_streams',
        'a',
        '-show_entries',
        'stream=index',
        '-of',
        'csv=p=0',
        entry.realPath,
      ]).timeout(_timeout);
      final hasAudio =
          result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty;
      _cache[key] = hasAudio;

      return hasAudio;
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'audio stream probe failed for ${entry.realPath}',
        error: error,
        stack: stack,
      );
      _cache[key] = false;

      return false;
    }
  }
}
