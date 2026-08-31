import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

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
/// terminal's pane; the file is deleted once handled. Terminal id `0` is
/// reserved and never assigned to a real terminal, so it always falls back
/// to whichever pane is currently active — the id an *external* shell
/// (one Waydir didn't spawn) should use, since it has no
/// `WAYDIR_TERMINAL_ID` of its own. On Windows, [persistCwdDirEnvVar] makes
/// `WAYDIR_CWD_DIR` available there too, in newly-opened shells.
///
/// The written path must be a native path Windows can resolve directly —
/// [Directory.existsSync] rejects anything else and the signal is dropped
/// silently. This matters for Git Bash / MSYS, where `$PWD` is a POSIX-style
/// path (e.g. `/c/Users/...`) that doesn't resolve; use `pwd -W` there
/// instead, which prints the Windows form.
///
/// One-time shell setup — `${WAYDIR_TERMINAL_ID:-0}` (bash) / the PowerShell
/// equivalent falls back to the reserved id `0` when run outside Waydir:
///   PowerShell:      `function wd { $id = if ($env:WAYDIR_TERMINAL_ID) { $env:WAYDIR_TERMINAL_ID } else { 0 }; (Get-Location).Path | Set-Content -NoNewline "$env:WAYDIR_CWD_DIR\$id.txt" }`
///   Git Bash (MSYS): `wd() { pwd -W > "$WAYDIR_CWD_DIR/${WAYDIR_TERMINAL_ID:-0}.txt"; }`
///   bash/zsh (Unix): `wd() { printf '%s' "$PWD" > "$WAYDIR_CWD_DIR/${WAYDIR_TERMINAL_ID:-0}.txt"; }`
class TerminalCwdSignal {
  TerminalCwdSignal._();

  static final _fileNamePattern = RegExp(r'^(\d+)\.txt$');

  static StreamSubscription<FileSystemEvent>? _subscription;
  static final Map<String, Timer> _debounce = {};

  static Future<String> directory() async {
    final dir = await AppDirs.support();

    return p.join(dir, 'cwd_signals');
  }

  /// Persists `WAYDIR_CWD_DIR=[dir]` as a Windows user environment variable
  /// (`HKCU\Environment`) and broadcasts the change, so shells opened after
  /// this runs — including ones Waydir never spawned — see it without a
  /// logout. A no-op on other platforms and if the value is already current.
  static void persistCwdDirEnvVar(String dir) {
    if (!Platform.isWindows) return;
    const name = 'WAYDIR_CWD_DIR';
    if (_readEnvVar(name) == dir) return;
    final hKeyPtr = calloc<IntPtr>();
    final subKeyPtr = 'Environment'.toNativeUtf16();
    try {
      final created = RegCreateKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        nullptr,
        0,
        KEY_WRITE,
        nullptr,
        hKeyPtr,
        nullptr,
      );
      if (created != ERROR_SUCCESS) return;
      final valueNamePtr = name.toNativeUtf16();
      final valuePtr = dir.toNativeUtf16();
      try {
        RegSetValueEx(
          hKeyPtr.value,
          valueNamePtr,
          0,
          REG_SZ,
          valuePtr.cast<Uint8>(),
          (dir.length + 1) * 2,
        );
      } finally {
        calloc.free(valueNamePtr);
        calloc.free(valuePtr);
      }
      RegCloseKey(hKeyPtr.value);
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to persist WAYDIR_CWD_DIR',
        error: e,
        stack: st,
      );

      return;
    } finally {
      calloc.free(subKeyPtr);
      calloc.free(hKeyPtr);
    }
    final lParamPtr = 'Environment'.toNativeUtf16();
    final resultPtr = calloc<IntPtr>();
    try {
      SendMessageTimeout(
        HWND_BROADCAST,
        WM_SETTINGCHANGE,
        0,
        lParamPtr.address,
        SMTO_ABORTIFHUNG,
        5000,
        resultPtr,
      );
    } finally {
      calloc.free(lParamPtr);
      calloc.free(resultPtr);
    }
  }

  static String? _readEnvVar(String name) {
    final hKeyPtr = calloc<IntPtr>();
    final subKeyPtr = 'Environment'.toNativeUtf16();
    try {
      final opened = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        KEY_READ,
        hKeyPtr,
      );
      if (opened != ERROR_SUCCESS) return null;
      final valueNamePtr = name.toNativeUtf16();
      final sizePtr = calloc<Uint32>();
      try {
        var status = RegQueryValueEx(
          hKeyPtr.value,
          valueNamePtr,
          nullptr,
          nullptr,
          nullptr,
          sizePtr,
        );
        if (status != ERROR_SUCCESS || sizePtr.value == 0) return null;
        final dataPtr = calloc<Uint8>(sizePtr.value);
        try {
          status = RegQueryValueEx(
            hKeyPtr.value,
            valueNamePtr,
            nullptr,
            nullptr,
            dataPtr,
            sizePtr,
          );
          if (status != ERROR_SUCCESS) return null;

          return dataPtr.cast<Utf16>().toDartString();
        } finally {
          calloc.free(dataPtr);
        }
      } finally {
        calloc.free(valueNamePtr);
        calloc.free(sizePtr);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(subKeyPtr);
      RegCloseKey(hKeyPtr.value);
      calloc.free(hKeyPtr);
    }
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
