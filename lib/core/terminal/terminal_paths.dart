import 'dart:io';

import 'package:path/path.dart' as p;

/// How a terminal's shell expects local paths to be spelled.
enum TerminalPathStyle { native, msys, cygwin, wsl }

/// Rewrites Windows paths for POSIX shells running on Windows, so text
/// inserted into a Git Bash, Cygwin or WSL terminal is a path that shell
/// can actually use (`/c/Users/x`, `/cygdrive/c/Users/x`, `/mnt/c/Users/x`).
class TerminalPaths {
  TerminalPaths._();

  static const _posixShells = {'bash', 'sh', 'zsh', 'dash', 'fish', 'ksh'};

  static TerminalPathStyle styleFor(String program, {bool? windows}) {
    if (!(windows ?? Platform.isWindows) || program.isEmpty) {
      return TerminalPathStyle.native;
    }
    final lower = program.replaceAll('/', r'\').toLowerCase();
    final name = p.windows.basenameWithoutExtension(lower);
    if (name == 'wsl') return TerminalPathStyle.wsl;
    if (!_posixShells.contains(name)) return TerminalPathStyle.native;
    if (lower.contains(r'\windows\system32\')) return TerminalPathStyle.wsl;
    if (lower.contains('cygwin')) return TerminalPathStyle.cygwin;

    return TerminalPathStyle.msys;
  }

  static String convert(String path, TerminalPathStyle style) {
    if (style == TerminalPathStyle.native) return path;
    final drive = RegExp(r'^([A-Za-z]):[\\/]?(.*)$').firstMatch(path);
    if (drive != null) {
      final letter = drive.group(1)!.toLowerCase();
      final rest = drive.group(2)!.replaceAll(r'\', '/');
      final root = switch (style) {
        TerminalPathStyle.cygwin => '/cygdrive/$letter',
        TerminalPathStyle.wsl => '/mnt/$letter',
        _ => '/$letter',
      };

      return rest.isEmpty ? root : '$root/$rest';
    }
    if (style == TerminalPathStyle.wsl) {
      final distro = RegExp(
        r'^[\\/]{2}(?:wsl\$|wsl\.localhost)[\\/][^\\/]+(.*)$',
        caseSensitive: false,
      ).firstMatch(path);
      if (distro != null) {
        final rest = distro.group(1)!.replaceAll(r'\', '/');

        return rest.isEmpty ? '/' : rest;
      }
      if (path.startsWith(r'\\')) return path;
    }

    return path.replaceAll(r'\', '/');
  }

  static final _posixDrive = RegExp(
    r'^/(?:cygdrive/|mnt/)?([A-Za-z])(?:/(.*))?$',
  );

  static String? toNative(String path, {bool? windows}) {
    if (!(windows ?? Platform.isWindows)) {
      return p.posix.isAbsolute(path) ? p.posix.normalize(path) : null;
    }
    final drive = _posixDrive.firstMatch(path);
    final String native;
    if (drive != null) {
      final letter = drive.group(1)!.toUpperCase();
      native = '$letter:\\${drive.group(2) ?? ''}';
    } else if (path.startsWith('//') || path.startsWith(r'\\')) {
      native = path.replaceAll('/', r'\');
    } else if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      native = path;
    } else {
      return null;
    }

    return p.windows.normalize(native);
  }

  static String? resolve(String cwd, String path, {bool? windows}) {
    final isWindows = windows ?? Platform.isWindows;
    final rooted =
        path.startsWith('/') ||
        (isWindows &&
            (path.startsWith(r'\') ||
                RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)));
    if (rooted) return toNative(path, windows: isWindows);
    final base = toNative(cwd, windows: isWindows);
    if (base == null) return null;
    final context = isWindows ? p.windows : p.posix;

    return context.normalize(context.join(base, path));
  }
}
