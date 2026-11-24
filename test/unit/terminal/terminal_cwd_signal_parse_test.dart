import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/terminal/msys_mounts.dart';
import 'package:waydir/core/terminal/terminal_paths.dart';
import 'package:waydir/features/panes/terminal_cwd_signal.dart';

void main() {
  group('TerminalPaths.toNative on Windows', () {
    String? native(String path) => TerminalPaths.toNative(path, windows: true);

    test('MSYS, Cygwin and WSL drive paths', () {
      expect(native('/c/Users/me/x.txt'), r'C:\Users\me\x.txt');
      expect(native('/cygdrive/d/data'), r'D:\data');
      expect(native('/mnt/q/a b'), r'Q:\a b');
    });

    test('drive roots', () {
      expect(native('/c'), r'C:\');
      expect(native('/c/'), r'C:\');
    });

    test('Windows paths are normalized', () {
      expect(native(r'C:\a\.\b\..\c'), r'C:\a\c');
      expect(native('C:/a/b'), r'C:\a\b');
      expect(native(r'C:\a\.'), r'C:\a');
    });

    test('UNC paths', () {
      expect(native('//server/share/x'), r'\\server\share\x');
      expect(native(r'\\server\share\x'), r'\\server\share\x');
    });

    test('POSIX paths with no Windows equivalent and relative paths', () {
      expect(native('/tmp'), isNull);
      expect(native('/usr/bin'), isNull);
      expect(native('sub/x'), isNull);
    });
  });

  test('TerminalPaths.toNative off Windows only normalizes', () {
    expect(
      TerminalPaths.toNative('/home/me/./a/../b', windows: false),
      '/home/me/b',
    );
    expect(TerminalPaths.toNative('a/b', windows: false), isNull);
  });

  group('TerminalCwdSignal.parse on Windows', () {
    String? parse(String content) =>
        TerminalCwdSignal.parse(content, windows: true);

    test('one absolute line, as older wd functions write it', () {
      expect(parse(r'C:\Users\me'), r'C:\Users\me');
      expect(parse('C:\\Users\\me\r\n'), r'C:\Users\me');
    });

    test('cwd only opens the cwd, normalized', () {
      expect(parse('/c/Users/me\n'), r'C:\Users\me');
      expect(parse('/c/Users/me/.'), r'C:\Users\me');
    });

    test('a relative argument is resolved against the cwd', () {
      expect(parse('/c/Users/me\n.'), r'C:\Users\me');
      expect(parse('/c/Users/me\n..'), r'C:\Users');
      expect(parse('/c/Users/me\n../you/x.txt'), r'C:\Users\you\x.txt');
      expect(parse('/c/Users/me\nsub dir/x.txt'), r'C:\Users\me\sub dir\x.txt');
    });

    test('an absolute argument ignores the cwd', () {
      expect(parse('/c/Users/me\n/d/data'), r'D:\data');
      expect(parse('/c/Users/me\nE:\\x'), r'E:\x');
    });

    test('unresolvable input is dropped', () {
      expect(parse(''), isNull);
      expect(parse('/tmp\nx'), isNull);
      expect(parse('/c/Users/me\n/tmp'), isNull);
    });
  });

  group('with the shell install mounts', () {
    const git = r'C:\Tools\git';
    const temp = r'C:\Users\me\AppData\Local\Temp';
    final msys = MsysMounts(
      root: git,
      mounts: MsysMounts.parseFstab(
        'none / cygdrive binary,posix=0,noacl,user 0 0\n'
        'none /tmp usertemp binary,posix=0,noacl 0 0\n'
        'D:/work /work ntfs binary 0 0\n',
        temp: temp,
      ),
    );
    String? parse(String content) =>
        TerminalCwdSignal.parse(content, windows: true, msys: msys);

    test('/tmp follows the usertemp mount', () {
      expect(parse('/c/Users/me\n/tmp'), temp);
      expect(parse('/c/Users/me\n/tmp/hoge'), '$temp\\hoge');
      expect(parse('/tmp/hoge\n.'), '$temp\\hoge');
      expect(parse('/tmp/hoge\n../x.txt'), '$temp\\x.txt');
    });

    test('other POSIX paths land under the install root', () {
      expect(parse('/c/Users/me\n/usr/bin'), '$git\\usr\\bin');
      expect(parse('/c/Users/me\n/etc/fstab'), '$git\\etc\\fstab');
    });

    test('an explicit fstab mount wins over the root', () {
      expect(parse('/c/Users/me\n/work/a'), r'D:\work\a');
      expect(parse('/c/Users/me\n/workshop'), '$git\\workshop');
    });

    test('drive paths are unaffected', () {
      expect(parse('/c/Users/me\n/d/data'), r'D:\data');
    });
  });

  test('TerminalCwdSignal.parse off Windows', () {
    expect(
      TerminalCwdSignal.parse('/home/me\n../you', windows: false),
      '/home/you',
    );
    expect(TerminalCwdSignal.parse('/home/me/.\n', windows: false), '/home/me');
  });
}
