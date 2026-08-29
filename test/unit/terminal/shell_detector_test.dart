import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/terminal/shell_detector.dart';
import 'package:waydir/core/terminal/windows_terminal_profiles.dart';

void main() {
  group('ShellCommand', () {
    test('encodes a plain path with no args as itself', () {
      final cmd = ShellCommand(r'C:\Windows\System32\cmd.exe');
      expect(cmd.encode(), r'C:\Windows\System32\cmd.exe');
    });

    test('round-trips program and args through encode/decode', () {
      final cmd = ShellCommand('wsl.exe', ['-d', 'Ubuntu']);
      final decoded = ShellCommand.decode(cmd.encode());
      expect(decoded.program, 'wsl.exe');
      expect(decoded.args, ['-d', 'Ubuntu']);
    });

    test('decodes a plain path (pre-args setting value) with no args', () {
      final decoded = ShellCommand.decode('/usr/bin/fish');
      expect(decoded.program, '/usr/bin/fish');
      expect(decoded.args, isEmpty);
    });

    test('falls back to a plain path for malformed JSON-looking values', () {
      final decoded = ShellCommand.decode('{not json');
      expect(decoded.program, '{not json');
      expect(decoded.args, isEmpty);
    });
  });

  group('ShellOption.toSettingValue', () {
    test('is the bare path when there are no args', () {
      const option = ShellOption(path: '/bin/zsh', label: 'zsh');
      expect(option.toSettingValue(), '/bin/zsh');
    });

    test('round-trips through ShellCommand.decode when there are args', () {
      const option = ShellOption(
        path: 'wsl.exe',
        args: ['-d', 'Ubuntu'],
        label: 'Ubuntu',
      );
      final decoded = ShellCommand.decode(option.toSettingValue());
      expect(decoded.program, 'wsl.exe');
      expect(decoded.args, ['-d', 'Ubuntu']);
    });
  });

  group('WindowsTerminalProfiles.parse', () {
    test('extracts program and args from a quoted commandline', () {
      final options = WindowsTerminalProfiles.parse('''
{
  "profiles": {
    "list": [
      {
        "name": "PowerShell 7",
        "commandline": "\\"C:\\\\Program Files\\\\PowerShell\\\\7\\\\pwsh.exe\\" -NoLogo"
      }
    ]
  }
}
''');
      expect(options, hasLength(1));
      expect(options.single.path, r'C:\Program Files\PowerShell\7\pwsh.exe');
      expect(options.single.args, ['-NoLogo']);
      expect(options.single.label, 'PowerShell 7');
    });

    test('maps a WSL-source profile to wsl.exe -d <name>', () {
      final options = WindowsTerminalProfiles.parse('''
{
  "profiles": {
    "list": [
      {"name": "Ubuntu", "source": "Windows.Terminal.Wsl"}
    ]
  }
}
''');
      expect(options.single.path, 'wsl.exe');
      expect(options.single.args, ['-d', 'Ubuntu']);
    });

    test('skips hidden profiles and Azure Cloud Shell', () {
      final options = WindowsTerminalProfiles.parse('''
{
  "profiles": {
    "list": [
      {"name": "Hidden", "commandline": "cmd.exe", "hidden": true},
      {"name": "Azure Cloud Shell", "source": "Windows.Terminal.Azure"}
    ]
  }
}
''');
      expect(options, isEmpty);
    });

    test('strips // line comments before parsing', () {
      final options = WindowsTerminalProfiles.parse('''
{
  // a top-level comment
  "profiles": {
    "list": [
      {"name": "cmd", "commandline": "cmd.exe"} // trailing comment
    ]
  }
}
''');
      expect(options.single.path, 'cmd.exe');
    });

    test('does not treat // inside a string value as a comment', () {
      final options = WindowsTerminalProfiles.parse('''
{
  "profiles": {
    "list": [
      {"name": "http://example", "commandline": "cmd.exe"}
    ]
  }
}
''');
      expect(options.single.label, 'http://example');
    });
  });
}
