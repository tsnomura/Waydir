import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/launchers/launcher_def.dart';
import 'package:waydir/features/launchers/launcher_runner.dart';

void main() {
  LauncherDef parse(Map<String, dynamic> json) => LauncherDef.fromJson(json);

  test('parses an open launcher', () {
    final def = parse({
      'id': 'f3d-step',
      'name': 'f3d (STEP)',
      'extensions': ['.STEP', 'stp'],
      'cmd': 'f3d',
      'args': ['--force-reader=STEP', '%FILE%'],
      'default': true,
    });

    expect(def.context, LauncherContext.open);
    expect(def.extensions, {'step', 'stp'});
    expect(def.matchesExtension('STP'), isTrue);
    expect(def.isDefault, isTrue);
  });

  test('compare launchers may omit extensions', () {
    final def = parse({
      'id': 'merge',
      'context': 'compare',
      'cmd': 'winxmerge',
      'args': ['%LEFT%', '%RIGHT%'],
    });

    expect(def.name, 'merge');
    expect(def.matchesExtension('m'), isTrue);
  });

  test('rejects open launchers without extensions', () {
    expect(
      () => parse({'id': 'x', 'cmd': 'x', 'args': <String>[]}),
      throwsFormatException,
    );
  });

  test('"*" matches every file, including ones without an extension', () {
    final def = parse({
      'id': 'any',
      'extensions': ['*'],
      'cmd': 'x',
      'args': ['%FILE%'],
    });

    expect(def.matchesAll, isTrue);
    expect(def.matchesExtension('txt'), isTrue);
    expect(def.matchesExtension(''), isTrue);
  });

  test('rejects default open launchers for "*"', () {
    expect(
      () => parse({
        'id': 'any',
        'extensions': ['*'],
        'cmd': 'x',
        'args': ['%FILE%'],
        'default': true,
      }),
      throwsFormatException,
    );
  });

  test('allows default compare launchers for "*"', () {
    final def = parse({
      'id': 'merge',
      'context': 'compare',
      'extensions': ['*'],
      'cmd': 'winxmerge',
      'args': ['%LEFT%', '%RIGHT%'],
      'default': true,
    });

    expect(def.isDefault, isTrue);
    expect(def.matchesExtension('m'), isTrue);
  });

  test('minFiles and maxFiles limit the selection size', () {
    final def = parse({
      'id': 'merge-files',
      'extensions': ['*'],
      'cmd': 'winxmerge',
      'args': ['%FILES%'],
      'minFiles': 2,
      'maxFiles': 3,
    });

    expect(def.acceptsCount(1), isFalse);
    expect(def.acceptsCount(2), isTrue);
    expect(def.acceptsCount(3), isTrue);
    expect(def.acceptsCount(4), isFalse);
    expect(LauncherRunner.commandLines(def, files: ['/a', '/b', '/c']), [
      ['/a', '/b', '/c'],
    ]);
  });

  test('rejects invalid file count limits', () {
    Map<String, dynamic> base() => {
      'id': 'x',
      'extensions': ['*'],
      'cmd': 'x',
      'args': ['%FILES%'],
    };

    expect(() => parse(base()..['minFiles'] = 0), throwsFormatException);
    expect(
      () => parse(
        base()
          ..['minFiles'] = 3
          ..['maxFiles'] = 2,
      ),
      throwsFormatException,
    );
  });

  test('%FILE% runs once per file, %FILES% once with all files', () {
    final single = parse({
      'id': 'a',
      'extensions': ['txt'],
      'cmd': 'a',
      'args': ['-o', '%FILE%'],
    });
    final multi = parse({
      'id': 'b',
      'extensions': ['txt'],
      'cmd': 'b',
      'args': ['--files', '%FILES%', '--dir=%DIR%'],
    });
    const files = ['/x/1.txt', '/x/2.txt'];

    expect(LauncherRunner.commandLines(single, files: files), [
      ['-o', '/x/1.txt'],
      ['-o', '/x/2.txt'],
    ]);
    expect(LauncherRunner.commandLines(multi, files: files), [
      ['--files', '/x/1.txt', '/x/2.txt', '--dir=/x'],
    ]);
  });

  test('%WAYDIR% resolves to the running executable', () {
    final def = parse({
      'id': 'ql',
      'extensions': ['md'],
      'cmd': '%WAYDIR%',
      'args': ['--quick-look', '%FILE%'],
    });

    expect(
      LauncherRunner.resolveCommand(def, waydir: '/opt/waydir'),
      '/opt/waydir',
    );
    expect(LauncherRunner.commandLines(def, files: ['/n/a.md', '/n/b.md']), [
      ['--quick-look', '/n/a.md'],
      ['--quick-look', '/n/b.md'],
    ]);
  });

  test('compare launchers get the left and right paths', () {
    final def = parse({
      'id': 'merge',
      'context': 'compare',
      'cmd': 'winxmerge',
      'args': ['%LEFT%', '%RIGHT%'],
    });

    expect(LauncherRunner.commandLines(def, left: '/l/a.m', right: '/r/a.m'), [
      ['/l/a.m', '/r/a.m'],
    ]);
  });
}
