import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../launchers/launcher_runner.dart';

/// Opens a file in a standalone `--quick-look` window (a separate Waydir
/// process), for Ctrl+Enter from Quick Look.
class QuickLookPopOut {
  QuickLookPopOut._();

  static String? pathFor(FileEntry entry) {
    final target = entry.ghostOf ?? entry;
    if (target.type != FileItemType.file) return null;
    final path = target.realPath;

    return File(path).existsSync() ? path : null;
  }

  static Future<bool> open(FileEntry entry) async {
    final path = pathFor(entry);
    if (path == null) return false;
    try {
      await Process.start(LauncherRunner.waydirExecutable, [
        '--quick-look',
        path,
      ], mode: ProcessStartMode.detached);

      return true;
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'failed to open $path in a Quick Look window',
        error: error,
        stack: stack,
      );

      return false;
    }
  }
}
