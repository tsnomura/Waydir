import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import 'windows_terminal_profiles.dart';

/// A shell available on the host so the built-in terminal can launch it.
class ShellOption {
  /// Path to the shell executable.
  final String path;

  /// Extra arguments to pass (e.g. `-d <distro>` for a WSL profile).
  final List<String> args;

  /// Display name (e.g. `bash`, `PowerShell 7`).
  final String label;

  const ShellOption({
    required this.path,
    required this.label,
    this.args = const [],
  });

  /// The value stored in [SettingsStore.terminalShell] when this option is
  /// picked. Plain when there are no args (backward compatible with settings
  /// saved before args existed), JSON-encoded otherwise.
  String toSettingValue() => ShellCommand(path, args).encode();
}

/// A resolved program + argv to launch as the terminal's shell, and its
/// (de)serialization to/from a single setting string.
class ShellCommand {
  final String program;
  final List<String> args;

  const ShellCommand(this.program, [this.args = const []]);

  String encode() =>
      args.isEmpty ? program : jsonEncode({'program': program, 'args': args});

  /// Decodes a value previously produced by [encode]. A plain path (no args,
  /// or a value saved before args existed) decodes to itself unchanged.
  static ShellCommand decode(String value) {
    if (value.startsWith('{')) {
      try {
        final map = jsonDecode(value);
        if (map is Map && map['program'] is String) {
          final args = (map['args'] as List?)?.whereType<String>().toList();

          return ShellCommand(map['program'] as String, args ?? const []);
        }
      } catch (_) {
        // Fall through to treating the value as a plain path.
      }
    }

    return ShellCommand(value);
  }
}

/// Discovers shells installed on the host so the user can pick one for the
/// built-in terminal. The detector only reports executables that actually
/// exist on disk; the caller adds a separate "system default" entry.
class ShellDetector {
  ShellDetector._();

  static List<ShellOption> detect() {
    if (Platform.isWindows) return _detectWindows();

    return _detectUnix();
  }

  /// The concrete shell used when the preference is "system default":
  /// `$SHELL` on Unix, PowerShell on Windows (falling back to whatever is
  /// available). Empty means "let the native pty pick" (Unix `$SHELL`).
  static String defaultShellPath() {
    if (!Platform.isWindows) return Platform.environment['SHELL'] ?? '';
    final shells = _detectWindows();
    for (final s in shells) {
      if (s.label.contains('PowerShell')) return s.path;
    }

    return shells.isEmpty ? '' : shells.first.path;
  }

  static List<ShellOption> _detectUnix() {
    final seen = <String>{};
    final out = <ShellOption>[];
    void add(String path) {
      final p = path.trim();
      if (p.isEmpty || !File(p).existsSync()) return;
      final name = p.split('/').last;
      if (!seen.add(name)) return;
      out.add(ShellOption(path: p, label: name));
    }

    final current = Platform.environment['SHELL'];
    if (current != null) add(current);

    try {
      final etc = File('/etc/shells');
      if (etc.existsSync()) {
        for (final line in etc.readAsLinesSync()) {
          final s = line.trim();
          if (s.isEmpty || s.startsWith('#')) continue;
          add(s);
        }
      }
    } catch (e, st) {
      log.warn('terminal', 'shell discovery failed', error: e, stack: st);
    }

    for (final p in const [
      '/bin/bash',
      '/usr/bin/bash',
      '/bin/zsh',
      '/usr/bin/zsh',
      '/usr/bin/fish',
      '/bin/fish',
      '/usr/bin/nu',
      '/bin/sh',
    ]) {
      add(p);
    }

    return out;
  }

  static List<ShellOption> _detectWindows() {
    final env = Platform.environment;
    final seen = <String>{};
    final out = <ShellOption>[];
    void add(String? path, String label) {
      if (path == null) return;
      final p = path.trim();
      final key = p.toLowerCase();
      if (p.isEmpty || seen.contains(key) || !File(p).existsSync()) return;
      seen.add(key);
      out.add(ShellOption(path: p, label: label));
    }

    final sysRoot = env['SystemRoot'] ?? r'C:\Windows';
    final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';

    add('$programFiles\\PowerShell\\7\\pwsh.exe', 'PowerShell 7');
    add(
      '$sysRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      'Windows PowerShell',
    );
    add(env['ComSpec'] ?? '$sysRoot\\System32\\cmd.exe', 'Command Prompt');
    add('$programFiles\\Git\\bin\\bash.exe', 'Git Bash');

    final labels = {for (final s in out) s.label.toLowerCase()};
    for (final profile in WindowsTerminalProfiles.detect()) {
      if (!labels.add(profile.label.toLowerCase())) continue;
      out.add(profile);
    }

    return out;
  }
}
