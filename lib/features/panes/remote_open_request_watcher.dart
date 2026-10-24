import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';

/// Lets a linked Waydir instance on another machine ask this one to open a
/// local directory, over a channel built on top of an SFTP connection that
/// machine already has into this one — this instance never accepts any
/// inbound connection of its own.
///
/// The linked instance writes the requested path into a file under
/// [directory] (via an ordinary SFTP write through its own, already-open
/// session to this host); this watches that directory and opens whatever
/// path each new file names, then deletes the file. See
/// `lib/features/panes/remote_sync_actions.dart` for the other side.
class RemoteOpenRequestWatcher {
  RemoteOpenRequestWatcher._();

  static StreamSubscription<FileSystemEvent>? _subscription;
  static final Map<String, Timer> _debounce = {};

  static Future<String> directory() async {
    final dir = await AppDirs.support();

    return p.join(dir, 'remote_open_requests');
  }

  /// Starts watching [directory] for incoming requests. `onPath` is called
  /// with the directory path each request names.
  static Future<void> start(void Function(String path) onPath) async {
    await stop();
    final dirPath = await directory();
    final dir = Directory(dirPath);
    try {
      dir.createSync(recursive: true);
    } catch (e, st) {
      log.warn(
        'remoteSync',
        'failed to create remote open request directory',
        error: e,
        stack: st,
      );

      return;
    }
    _subscription = dir
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
        .listen((event) {
          final name = p.basename(event.path);
          if (!name.endsWith('.txt')) return;
          _debounce[name]?.cancel();
          _debounce[name] = Timer(const Duration(milliseconds: 150), () {
            _debounce.remove(name);
            _handleFile(File(event.path), onPath);
          });
        });
  }

  static void _handleFile(File file, void Function(String path) onPath) {
    final String content;
    try {
      content = file.readAsStringSync().trim();
    } catch (e, st) {
      log.warn(
        'remoteSync',
        'failed to read remote open request file',
        error: e,
        stack: st,
      );

      return;
    }
    try {
      file.deleteSync();
    } catch (_) {
      // Best-effort cleanup; a leftover file just gets overwritten next time.
    }
    if (content.isEmpty || !Directory(content).existsSync()) return;
    onPath(content);
  }

  static Future<void> stop() async {
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    _debounce.clear();
    await _subscription?.cancel();
    _subscription = null;
  }
}
