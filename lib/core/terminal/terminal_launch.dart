import '../../features/locations/location_resolver.dart';
import '../../features/locations/location_uri.dart';
import '../platform/platform_paths.dart';
import '../settings/settings_store.dart';
import 'sftp_terminal.dart';
import 'shell_detector.dart';

class TerminalLaunchSpec {
  final String shell;
  final List<String> args;
  final String cwd;

  const TerminalLaunchSpec({
    this.shell = '',
    this.args = const [],
    required this.cwd,
  });
}

class TerminalLaunch {
  TerminalLaunch._();

  static TerminalLaunchSpec resolve(String path) {
    if (PlatformPaths.isSftpUri(path)) {
      final uri = LocationUri.parse(path);
      final remote = SftpTerminal.command(uri);
      if (remote != null) {
        return TerminalLaunchSpec(
          shell: remote.program,
          args: remote.args,
          cwd: PlatformPaths.homePath,
        );
      }

      return TerminalLaunchSpec(cwd: PlatformPaths.homePath);
    }
    if (PlatformPaths.isSmbUri(path)) {
      final physical = LocationResolver.logicalToPhysical(path);

      return _localShellSpec(physical ?? PlatformPaths.homePath);
    }

    return _localShellSpec(path);
  }

  /// Launch spec for an explicit shell choice (a value produced by
  /// [ShellOption.toSettingValue]) at [cwd]. An empty [shell] (e.g. the
  /// "system default" choice) falls back to the platform default.
  static TerminalLaunchSpec forShell(String shell, String cwd) {
    if (shell.isEmpty) return _localShellSpec(cwd);
    final command = ShellCommand.decode(shell);

    return TerminalLaunchSpec(
      cwd: cwd,
      shell: command.program,
      args: command.args,
    );
  }

  /// Launch spec for a WSL distribution. The target directory is passed via
  /// `--cd` (WSL translates Windows and `\\wsl.localhost` paths); the Windows
  /// process cwd is left at the home path because CreateProcess rejects a UNC
  /// working directory.
  static TerminalLaunchSpec forWsl(String distribution, String cwd) {
    return TerminalLaunchSpec(
      cwd: PlatformPaths.homePath,
      shell: 'wsl.exe',
      args: ['-d', distribution, '--cd', cwd],
    );
  }

  /// Launch spec for a local session at [cwd], from the user's shell
  /// preference. Empty or `'system'` resolves to the platform's sensible
  /// default (PowerShell on Windows, `$SHELL` on Unix); anything else is a
  /// value produced by [ShellOption.toSettingValue] (a plain path, or a
  /// JSON-encoded program+args for a shell with arguments, e.g. a Windows
  /// Terminal WSL profile).
  static TerminalLaunchSpec _localShellSpec(String cwd) {
    final pref = SettingsStore.instance.terminalShell.value;
    if (pref.isEmpty || pref == 'system') {
      return TerminalLaunchSpec(
        cwd: cwd,
        shell: ShellDetector.defaultShellPath(),
      );
    }
    final command = ShellCommand.decode(pref);

    return TerminalLaunchSpec(
      cwd: cwd,
      shell: command.program,
      args: command.args,
    );
  }
}
