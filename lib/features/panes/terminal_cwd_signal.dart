import 'dart:async';
import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';

/// Watches a single plain-text file for a directory path to open, as a
/// no-protocol bridge from any shell into the active pane — like typing a
/// command instead of `ls` that shows the result in a tab. Whatever writes
/// the file last wins; there's no per-terminal identity, so it always opens
/// in whichever pane is currently active.
///
/// One-time shell setup, substituting the path from [filePath]:
///   PowerShell: `function wd { (Get-Location).Path | Set-Content -NoNewline PATH }`
///   bash/zsh:   `wd() { printf '%s' "$PWD" > PATH; }`
class TerminalCwdSignal {
  TerminalCwdSignal._();

  static StreamSubscription<FileSystemEvent>? _subscription;
  static Timer? _debounce;

  static Future<String> filePath() async {
    final dir = await AppDirs.support();

    return '$dir${Platform.pathSeparator}cwd_signal.txt';
  }

  static Future<void> start(void Function(String path) onPath) async {
    await stop();
    final path = await filePath();
    final file = File(path);
    try {
      if (!file.existsSync()) file.createSync(recursive: true);
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to create cwd signal file',
        error: e,
        stack: st,
      );

      return;
    }
    _subscription = file.watch(events: FileSystemEvent.modify).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(milliseconds: 150),
        () => _handleChange(file, onPath),
      );
    });
  }

  static void _handleChange(File file, void Function(String path) onPath) {
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
    if (content.isEmpty || !Directory(content).existsSync()) return;
    onPath(content);
  }

  static Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
