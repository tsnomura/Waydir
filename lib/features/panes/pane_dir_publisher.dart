import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';

/// The reverse of `TerminalCwdSignal`: publishes each pane's current
/// directory to a plain-text file, so a shell can `cd` into whatever a pane
/// is showing instead of the other way around.
///
/// Terminals Waydir spawns get `WAYDIR_ORIGIN_PANE` (the pane index, `0` or
/// `1`) in their environment. `$WAYDIR_PANE_DIR_ROOT/$WAYDIR_ORIGIN_PANE.txt`
/// always holds that pane's current directory; `active.txt` always holds
/// whichever pane currently has focus — the file an *external* shell (no
/// `WAYDIR_ORIGIN_PANE` of its own) should read.
///
/// One-time shell setup — falls back to `active.txt` outside Waydir:
///   PowerShell:      `function wcd { $pane = if ($env:WAYDIR_ORIGIN_PANE) { $env:WAYDIR_ORIGIN_PANE } else { 'active' }; Set-Location (Get-Content "$env:WAYDIR_PANE_DIR_ROOT\$pane.txt") }`
///   Git Bash (MSYS): `wcd() { cd "$(cat "$WAYDIR_PANE_DIR_ROOT/${WAYDIR_ORIGIN_PANE:-active}.txt")"; }`
///   bash/zsh (Unix): `wcd() { cd "$(cat "$WAYDIR_PANE_DIR_ROOT/${WAYDIR_ORIGIN_PANE:-active}.txt")"; }`
class PaneDirPublisher {
  PaneDirPublisher._();

  static final Map<String, String> _lastWritten = {};

  static Future<String> directory() async {
    final dir = await AppDirs.support();

    return p.join(dir, 'pane_dirs');
  }

  /// Writes `key.txt` = [path] under [dirRoot], skipping the write if
  /// unchanged since the last call for that key.
  static void publish(String dirRoot, String key, String path) {
    if (_lastWritten[key] == path) return;
    try {
      File(p.join(dirRoot, '$key.txt')).writeAsStringSync(path);
      _lastWritten[key] = path;
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to publish pane dir for $key',
        error: e,
        stack: st,
      );
    }
  }
}
