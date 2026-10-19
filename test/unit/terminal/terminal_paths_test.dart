import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/terminal/terminal_paths.dart';

void main() {
  group('TerminalPaths.styleFor', () {
    TerminalPathStyle style(String program) =>
        TerminalPaths.styleFor(program, windows: true);

    test('Git Bash and MSYS2 shells use MSYS paths', () {
      expect(
        style(r'C:\Users\me\scoop\apps\git\current\bin\bash.exe'),
        TerminalPathStyle.msys,
      );
      expect(
        style(r'C:\Program Files\Git\bin\bash.exe'),
        TerminalPathStyle.msys,
      );
      expect(style(r'C:\msys64\usr\bin\zsh.exe'), TerminalPathStyle.msys);
    });

    test('Cygwin shells use /cygdrive paths', () {
      expect(style(r'C:\cygwin64\bin\bash.exe'), TerminalPathStyle.cygwin);
    });

    test('wsl.exe and the System32 bash launcher use WSL paths', () {
      expect(style('wsl.exe'), TerminalPathStyle.wsl);
      expect(style(r'C:\Windows\System32\bash.exe'), TerminalPathStyle.wsl);
    });

    test('PowerShell, cmd and ssh keep native paths', () {
      expect(
        style(r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'),
        TerminalPathStyle.native,
      );
      expect(style('cmd.exe'), TerminalPathStyle.native);
      expect(style('ssh'), TerminalPathStyle.native);
      expect(style(''), TerminalPathStyle.native);
    });

    test('off Windows every shell is native', () {
      expect(
        TerminalPaths.styleFor('/bin/bash', windows: false),
        TerminalPathStyle.native,
      );
    });
  });

  group('TerminalPaths.convert', () {
    test('native leaves the path alone', () {
      expect(
        TerminalPaths.convert(r'C:\a\b c.txt', TerminalPathStyle.native),
        r'C:\a\b c.txt',
      );
    });

    test('drive paths per style', () {
      const path = r'Q:\20261018_waydir\my file.txt';
      expect(
        TerminalPaths.convert(path, TerminalPathStyle.msys),
        '/q/20261018_waydir/my file.txt',
      );
      expect(
        TerminalPaths.convert(path, TerminalPathStyle.cygwin),
        '/cygdrive/q/20261018_waydir/my file.txt',
      );
      expect(
        TerminalPaths.convert(path, TerminalPathStyle.wsl),
        '/mnt/q/20261018_waydir/my file.txt',
      );
    });

    test('drive roots', () {
      expect(TerminalPaths.convert(r'C:\', TerminalPathStyle.msys), '/c');
      expect(TerminalPaths.convert('C:', TerminalPathStyle.wsl), '/mnt/c');
    });

    test('relative paths only switch separators', () {
      expect(
        TerminalPaths.convert(r'..\sub\x.txt', TerminalPathStyle.msys),
        '../sub/x.txt',
      );
    });

    test('UNC paths become // paths for MSYS', () {
      expect(
        TerminalPaths.convert(r'\\server\share\x.txt', TerminalPathStyle.msys),
        '//server/share/x.txt',
      );
    });

    test('WSL distro paths map into the distro, other UNC stays', () {
      expect(
        TerminalPaths.convert(
          r'\\wsl.localhost\Ubuntu\home\me\x.txt',
          TerminalPathStyle.wsl,
        ),
        '/home/me/x.txt',
      );
      expect(
        TerminalPaths.convert(r'\\wsl$\Ubuntu', TerminalPathStyle.wsl),
        '/',
      );
      expect(
        TerminalPaths.convert(r'\\server\share\x.txt', TerminalPathStyle.wsl),
        r'\\server\share\x.txt',
      );
    });
  });
}
