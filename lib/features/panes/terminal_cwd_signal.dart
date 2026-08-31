import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';

/// A file-per-terminal bridge from any shell into the pane that owns it —
/// like typing a command instead of `ls` that shows the result in a tab, but
/// (unlike a single shared file) it knows which terminal sent it, so it
/// opens in the right pane regardless of which one currently has UI focus.
///
/// Each terminal Waydir spawns gets `WAYDIR_TERMINAL_ID` and `WAYDIR_CWD_DIR`
/// in its environment. Writing the current directory to
/// `$WAYDIR_CWD_DIR/$WAYDIR_TERMINAL_ID.txt` is picked up and routed to that
/// terminal's pane; the file is deleted once handled.
///
/// One-time shell setup:
///   PowerShell: `function wd { (Get-Location).Path | Set-Content -NoNewline "$env:WAYDIR_CWD_DIR\$env:WAYDIR_TERMINAL_ID.txt" }`
///   bash/zsh:   `wd() { printf '%s' "$PWD" > "$WAYDIR_CWD_DIR/$WAYDIR_TERMINAL_ID.txt"; }`
class TerminalCwdSignal {
  TerminalCwdSignal._();

  static final _fileNamePattern = RegExp(r'^(\d+)\.txt$');

  static StreamSubscription<FileSystemEvent>? _subscription;
  static final Map<String, Timer> _debounce = {};

  static Future<String> directory() async {
    final dir = await AppDirs.support();

    return p.join(dir, 'cwd_signals');
  }

  /// Starts watching [directory]'s signal directory. `onSignal` is called
  /// with the terminal id and the directory path it reported.
  static Future<void> start(
    void Function(int terminalId, String path) onSignal,
  ) async {
    await stop();
    final dirPath = await directory();
    final dir = Directory(dirPath);
    try {
      dir.createSync(recursive: true);
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to create cwd signal directory',
        error: e,
        stack: st,
      );

      return;
    }
    _subscription = dir
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
        .listen((event) {
          final name = p.basename(event.path);
          if (!_fileNamePattern.hasMatch(name)) return;
          _debounce[name]?.cancel();
          _debounce[name] = Timer(const Duration(milliseconds: 150), () {
            _debounce.remove(name);
            _handleFile(File(event.path), name, onSignal);
          });
        });
  }

  static void _handleFile(
    File file,
    String name,
    void Function(int terminalId, String path) onSignal,
  ) {
    final id = int.tryParse(_fileNamePattern.firstMatch(name)!.group(1)!);
    if (id == null) return;
    final String content;
    try {
      content = file.readAsStringSync().trim();
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to read cwd signal file',
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
    onSignal(id, content);
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
