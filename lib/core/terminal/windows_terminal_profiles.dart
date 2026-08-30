import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import 'shell_detector.dart' show ShellOption;

/// Reads shell profiles from Windows Terminal's `settings.json`, if
/// installed, so the terminal shell picker can offer the user's own WT
/// profiles (custom PowerShell flavors, WSL distros, SSH targets, etc.)
/// alongside the built-in defaults.
class WindowsTerminalProfiles {
  WindowsTerminalProfiles._();

  static List<ShellOption> detect() {
    final file = _findSettingsFile();
    if (file == null) return const [];
    try {
      return parse(file.readAsStringSync());
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to read Windows Terminal profiles',
        error: e,
        stack: st,
      );

      return const [];
    }
  }

  /// Parses the raw contents of a Windows Terminal `settings.json` into the
  /// shell options it offers. Exposed for testing; [detect] is the entry
  /// point callers should use.
  static List<ShellOption> parse(String raw) {
    final decoded = jsonDecode(_stripLineComments(raw));
    if (decoded is! Map) return const [];
    final profiles = decoded['profiles'];
    final list = profiles is Map ? profiles['list'] : profiles;
    if (list is! List) return const [];
    final out = <ShellOption>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final option = _toShellOption(entry);
      if (option != null) out.add(option);
    }

    return out;
  }

  static ShellOption? _toShellOption(Map entry) {
    if (entry['hidden'] == true) return null;
    final name = entry['name'];
    if (name is! String || name.isEmpty) return null;
    final source = entry['source'];
    if (source == 'Windows.Terminal.Wsl') {
      return ShellOption(path: 'wsl.exe', args: ['-d', name], label: name);
    }
    if (source == 'Windows.Terminal.Azure') return null;
    final commandline = entry['commandline'];
    if (commandline is! String || commandline.trim().isEmpty) return null;
    final tokens = _tokenize(_expandEnvVars(commandline.trim()));
    if (tokens.isEmpty) return null;

    return ShellOption(
      path: tokens.first,
      args: tokens.skip(1).toList(),
      label: name,
    );
  }

  /// Expands `%VAR%` references the way Windows Terminal does before it
  /// spawns a profile's `commandline` (e.g. `%SystemRoot%`, `%USERPROFILE%`).
  /// Lookups are case-insensitive, matching Windows env var semantics.
  /// Unknown variables are left untouched.
  static String _expandEnvVars(String value) {
    final env = Platform.environment;

    return value.replaceAllMapped(RegExp('%([^%]+)%'), (match) {
      final name = match.group(1)!;
      for (final entry in env.entries) {
        if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
      }

      return match.group(0)!;
    });
  }

  static File? _findSettingsFile() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return null;
    for (final pkg in const [
      'Microsoft.WindowsTerminal_8wekyb3d8bbwe',
      'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe',
    ]) {
      final packaged = File(
        '$local\\Packages\\$pkg\\LocalState\\settings.json',
      );
      if (packaged.existsSync()) return packaged;
    }
    final unpackaged = File(
      '$local\\Microsoft\\Windows Terminal\\settings.json',
    );

    return unpackaged.existsSync() ? unpackaged : null;
  }

  /// Strips `//` line comments that Windows Terminal's settings.json allows,
  /// without touching `//` inside string literals.
  static String _stripLineComments(String source) {
    final out = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (inString) {
        out.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        out.write(c);
        continue;
      }
      if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        out.write('\n');
        continue;
      }
      out.write(c);
    }

    return out.toString();
  }

  /// Splits a Windows command line into program + args, honoring the
  /// double-quoted segments Windows Terminal uses for paths with spaces.
  static List<String> _tokenize(String commandline) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < commandline.length; i++) {
      final c = commandline[i];
      if (c == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (c == ' ' && !inQuotes) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
        continue;
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());

    return tokens;
  }
}
