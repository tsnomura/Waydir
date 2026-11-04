import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/platform/app_dirs.dart';
import '../../core/platform/user_tmp_dir.dart';
import '../../core/terminal/terminal_paths.dart';

/// A file-per-terminal bridge from any shell into the pane that owns it —
/// like typing a command instead of `ls` that shows the result in a tab, but
/// (unlike a single shared file) it knows which terminal sent it, so it
/// opens in the right pane regardless of which one currently has UI focus.
///
/// Each terminal Waydir spawns gets `WAYDIR_TERMINAL_ID` and `WAYDIR_CWD_DIR`
/// in its environment. Writing the current directory to
/// `$WAYDIR_CWD_DIR/$WAYDIR_TERMINAL_ID.txt` is picked up and routed to that
/// terminal's pane; the file is deleted once handled. Terminal id `0` is
/// reserved and never assigned to a real terminal, so it always falls back
/// to whichever pane is currently active — the id an *external* shell
/// (one Waydir didn't spawn) should use, since it has no
/// `WAYDIR_TERMINAL_ID` of its own. Persisting `WAYDIR_CWD_DIR` as a user
/// env var (see `WindowsEnvVars` on Windows, `UnixEnvVars` on Linux/macOS)
/// makes it available there too, in newly-opened shells.
///
/// The file holds the shell's current directory on the first line and,
/// optionally, a path on the second (default `.`), which is resolved
/// against the first and normalized. Git Bash / Cygwin / WSL spellings
/// (`/c/Users/...`, `/cygdrive/c/...`, `/mnt/c/...`) are converted to
/// Windows paths, so a shell needs no `cygpath`; a POSIX path with no
/// Windows equivalent (MSYS's own `/tmp`) is dropped silently, as is a path
/// that doesn't exist. A single absolute path (the older one-line form)
/// still works.
///
/// A file path opens its folder with the cursor on the file.
///
/// One-time shell setup — `${WAYDIR_TERMINAL_ID:-0}` (bash) / the PowerShell
/// equivalent falls back to the reserved id `0` when run outside Waydir:
///   PowerShell:      `function wd { param([string]$Path = '.') $id = if ($env:WAYDIR_TERMINAL_ID) { $env:WAYDIR_TERMINAL_ID } else { 0 }; (Resolve-Path -LiteralPath $Path).ProviderPath | Set-Content -NoNewline -Encoding UTF8 "$env:WAYDIR_CWD_DIR\$id.txt" }`
///   bash/zsh (Git Bash and Unix): `wd() { printf '%s\n%s' "$PWD" "$1" > "$WAYDIR_CWD_DIR/${WAYDIR_TERMINAL_ID:-0}.txt"; }`
class TerminalCwdSignal {
  TerminalCwdSignal._();

  static final _fileNamePattern = RegExp(r'^(\d+)\.txt$');

  static StreamSubscription<FileSystemEvent>? _subscription;
  static final Map<String, Timer> _debounce = {};
  static Timer? _presence;
  static Timer? _restartTimer;

  static Future<String>? _directory;
  static String? _tmpRoot;

  static Future<String> directory() {
    return _directory ??= _resolveDirectory();
  }

  static Future<String> _resolveDirectory() async {
    final tmp = await UserTmpDir.path();
    if (tmp != null && await UserTmpDir.ensure(tmp)) {
      _tmpRoot = tmp;

      return p.join(tmp, 'signals');
    }
    final dir = await AppDirs.support();

    return p.join(dir, 'cwd_signals');
  }

  /// Starts watching [directory]'s signal directory. `onSignal` is called
  /// with the terminal id and the directory to open; when the reported path
  /// is a file, the directory is its parent and `cursor` is the file.
  static Future<void> start(
    void Function(int terminalId, String dir, String? cursor) onSignal,
  ) async {
    await stop();
    final dirPath = await directory();
    final dir = Directory(dirPath);
    final tmpRoot = _tmpRoot;
    if (tmpRoot != null && !await UserTmpDir.ensure(tmpRoot)) {
      log.warn('terminal', 'cwd signal directory $tmpRoot is not usable');

      return;
    }
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
        .listen(
          (event) {
            final name = p.basename(event.path);
            if (!_fileNamePattern.hasMatch(name)) return;
            _debounce[name]?.cancel();
            _debounce[name] = Timer(const Duration(milliseconds: 150), () {
              _debounce.remove(name);
              _handleFile(File(event.path), name, onSignal);
            });
          },
          onDone: () => _restart(onSignal),
          onError: (Object e) {
            log.warn('terminal', 'cwd signal watch failed', error: e);
            _restart(onSignal);
          },
          cancelOnError: true,
        );
    _presence = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!await dir.exists()) _restart(onSignal);
    });
  }

  static void _restart(
    void Function(int terminalId, String dir, String? cursor) onSignal,
  ) {
    if (_restartTimer != null) return;
    _restartTimer = Timer(const Duration(seconds: 1), () {
      _restartTimer = null;
      start(onSignal);
    });
  }

  static void _handleFile(
    File file,
    String name,
    void Function(int terminalId, String dir, String? cursor) onSignal,
  ) {
    final id = int.tryParse(_fileNamePattern.firstMatch(name)!.group(1)!);
    if (id == null) return;
    final String content;
    try {
      content = file.readAsStringSync();
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
    final path = parse(content);
    if (path == null) return;
    if (Directory(path).existsSync()) {
      onSignal(id, path, null);
    } else if (File(path).existsSync()) {
      onSignal(id, p.dirname(path), path);
    }
  }

  static String? parse(String content, {bool? windows}) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .toList(growable: false);
    final cwd = lines.first;
    if (cwd.isEmpty) return null;
    final arg = lines.length > 1 ? lines[1] : '';

    return TerminalPaths.resolve(
      cwd,
      arg.isEmpty ? '.' : arg,
      windows: windows,
    );
  }

  static Future<void> stop() async {
    _presence?.cancel();
    _presence = null;
    _restartTimer?.cancel();
    _restartTimer = null;
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    _debounce.clear();
    await _subscription?.cancel();
    _subscription = null;
  }
}
