@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/features/plugins/plugin_ffi.dart';

const _init = 'docs/examples/plugins/send-to-terminal/init.lua';

void main() {
  tearDownAll(PluginFfi.shutdown);

  Future<List<Map<String, dynamic>>> invoke(
    String action,
    List<String> paths, {
    required String dir,
    String? other,
  }) async {
    final raw = await PluginFfi.invoke(
      initLuaPath: _init,
      actionId: action,
      ctxJson: jsonEncode({
        'paths': paths,
        'dir': dir,
        'plugin_dir': p.dirname(_init),
        if (other != null) 'other_pane': {'dir': other},
      }),
    );
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    expect(json['ok'], isTrue, reason: '${json['error']}');

    return (json['effects'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> terminal(
    String action,
    List<String> paths, {
    required String dir,
    String? other,
  }) async {
    final fx = await invoke(action, paths, dir: dir, other: other);

    return fx.singleWhere((e) => e['type'] == 'terminal');
  }

  test('registers one context entry per template in one submenu', () async {
    final json =
        jsonDecode((await PluginFfi.load(_init))!) as Map<String, dynamic>;
    final contributions = (json['contributions'] as List).cast<Map>();
    expect(contributions.map((c) => c['id']), [
      'cp',
      'robocopy',
      'rsync',
      'scp',
    ]);
    expect(contributions.map((c) => c['group']).toSet(), {'Send to terminal'});
    expect(contributions.map((c) => c['menu']).toSet(), {'context'});
  });

  group('template files', () {
    late Directory plugin;

    setUp(() {
      plugin = Directory.systemTemp.createTempSync('waydir_stt_plugin');
      File(
        p.join(p.dirname(_init), 'init.lua'),
      ).copySync(p.join(plugin.path, 'init.lua'));
      File(
        p.join(p.dirname(_init), 'manifest.json'),
      ).copySync(p.join(plugin.path, 'manifest.json'));
      Directory(p.join(plugin.path, 'nested.json')).createSync();
      File(p.join(plugin.path, 'echo.json')).writeAsStringSync(
        jsonEncode({
          'title': 'Echo each',
          'command': 'echo {name} in {parent}',
          'each': true,
          'join': '; ',
          'quote': 'posix',
        }),
      );
      File(p.join(plugin.path, 'broken.json')).writeAsStringSync('{');
      File(
        p.join(plugin.path, 'untitled.json'),
      ).writeAsStringSync(jsonEncode({'command': 'true'}));
      File(p.join(plugin.path, 'notes.txt')).writeAsStringSync('x');
    });

    tearDown(() => plugin.deleteSync(recursive: true));

    test('loads only well-formed .json files', () async {
      final json =
          jsonDecode((await PluginFfi.load(p.join(plugin.path, 'init.lua')))!)
              as Map<String, dynamic>;
      final contributions = (json['contributions'] as List).cast<Map>();
      expect(contributions.map((c) => c['id']), ['echo']);
      expect(contributions.single['title'], 'Echo each');
    });

    test('fills an each template once per target', () async {
      final raw = await PluginFfi.invoke(
        initLuaPath: p.join(plugin.path, 'init.lua'),
        actionId: 'echo',
        ctxJson: jsonEncode({
          'paths': ['/mnt/a/x y', '/mnt/b/z'],
          'dir': '/mnt/a',
        }),
      );
      final json = jsonDecode(raw!) as Map<String, dynamic>;
      expect(json['ok'], isTrue, reason: '${json['error']}');
      final fx = (json['effects'] as List).cast<Map<String, dynamic>>();
      expect(
        fx.singleWhere((e) => e['type'] == 'terminal')['input'],
        "echo 'x y' in /mnt/a; echo z in /mnt/b",
      );
    });
  });

  group('rsync and cp', () {
    test('list every target before the destination', () async {
      final fx = await terminal(
        'rsync',
        ['/mnt/project/eo_06', '/mnt/project/b.txt'],
        dir: '/mnt/project',
        other: '/mnt/backup',
      );
      expect(
        fx['input'],
        'rsync -a -z --progress /mnt/project/eo_06 /mnt/project/b.txt '
        '/mnt/backup',
      );
      expect(fx['run'], isFalse);
      expect(fx['cwd'], isNull);
    });

    test('single-quote paths with spaces and quotes', () async {
      final fx = await terminal(
        'cp',
        ["/mnt/my project/it's"],
        dir: '/mnt/my project',
        other: '/mnt/back up',
      );
      expect(fx['input'], r"cp -r '/mnt/my project/it'\''s' '/mnt/back up'");
    });

    test('fall back to the current folder without a second pane', () async {
      final fx = await terminal('cp', ['/mnt/a/x'], dir: '/mnt/a');
      expect(fx['input'], 'cp -r /mnt/a/x /mnt/a');
    });

    test('refuse to run on Windows paths', () async {
      final fx = await invoke(
        'rsync',
        [r'X:\project\a'],
        dir: r'X:\project',
        other: r'N:\backup',
      );
      expect(fx.where((e) => e['type'] == 'terminal'), isEmpty);
      expect(fx.single['type'], 'toast');
    });
  });

  group('robocopy', () {
    test('opens cmd.exe and groups loose files by folder', () async {
      final fx = await terminal(
        'robocopy',
        [r'X:\project\a.txt', r'X:\project\b c.txt', r'X:\other\d.txt'],
        dir: r'X:\project',
        other: r'N:\backup',
      );
      expect(fx['shell'], 'cmd.exe');
      expect(
        fx['input'],
        r'robocopy "X:\project" "N:\backup" "a.txt" "b c.txt" /MT:8 /Z && '
        r'robocopy "X:\other" "N:\backup" "d.txt" /MT:8 /Z',
      );
    });

    test('copies a folder into a same-named subfolder', () async {
      final tmp = Directory.systemTemp.createTempSync('waydir_stt_test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final folder = Directory(p.join(tmp.path, 'eo 06'))..createSync();
      final file = File(p.join(tmp.path, 'notes.txt'))..writeAsStringSync('x');
      final fx = await terminal(
        'robocopy',
        [folder.path, file.path],
        dir: tmp.path,
        other: r'N:\',
      );
      expect(
        fx['input'],
        'robocopy "${folder.path}" "N:\\eo 06" /E /MT:8 /Z && '
        'robocopy "${tmp.path}" "N:\\" "notes.txt" /MT:8 /Z',
      );
    }, skip: !Platform.isWindows);

    test('refuses to run on POSIX paths', () async {
      final fx = await invoke(
        'robocopy',
        ['/mnt/a'],
        dir: '/mnt',
        other: '/mnt/b',
      );
      expect(fx.single['type'], 'toast');
    });
  });

  group('scp', () {
    test('uploads to an sftp destination from the home folder', () async {
      final fx = await terminal(
        'scp',
        ['/local/eo_06'],
        dir: '/local',
        other: 'sftp://user@example.com/remote/backup',
      );
      expect(fx['cwd'], '~');
      expect(
        fx['input'],
        'scp -r -C /local/eo_06 user@example.com:/remote/backup',
      );
    });

    test('quotes for cmd when a Windows path is involved', () async {
      final fx = await terminal(
        'scp',
        ['sftp://user@example.com/remote/eo_06'],
        dir: 'sftp://user@example.com/remote',
        other: r'C:\local\backup',
      );
      expect(
        fx['input'],
        r'scp -r -C "user@example.com:/remote/eo_06" "C:\local\backup"',
      );
    });

    test('adds -P for a non-default port only', () async {
      final custom = await terminal(
        'scp',
        ['sftp://user@example.com:2222/remote/eo_06'],
        dir: 'sftp://user@example.com:2222/remote',
        other: '/local/backup',
      );
      expect(
        custom['input'],
        'scp -r -C -P 2222 user@example.com:/remote/eo_06 /local/backup',
      );
      final standard = await terminal(
        'scp',
        ['sftp://user@example.com:22/remote/eo_06'],
        dir: 'sftp://user@example.com:22/remote',
        other: '/local/backup',
      );
      expect(standard['input'], isNot(contains('-P')));
    });

    test('omits the user when the URI has none', () async {
      final fx = await terminal(
        'scp',
        ['sftp://example.com/remote/eo_06'],
        dir: 'sftp://example.com/remote',
        other: '/local/backup',
      );
      expect(fx['input'], 'scp -r -C example.com:/remote/eo_06 /local/backup');
    });
  });
}
