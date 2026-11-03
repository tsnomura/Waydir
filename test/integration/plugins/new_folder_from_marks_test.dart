@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/features/plugins/plugin_ffi.dart';

const _init = 'docs/examples/plugins/new-folder-from-marks/init.lua';
const _action = 'new_folder_from_marks';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('waydir_nffm_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  tearDownAll(PluginFfi.shutdown);

  List<String> files(List<String> names) {
    return [
      for (final n in names)
        (File(p.join(tmp.path, n))..writeAsStringSync('x')).path,
    ];
  }

  Future<List<Map<String, dynamic>>> invoke(
    List<String> paths, {
    String? dir,
    Map<String, dynamic>? form,
    Map<String, dynamic>? location,
  }) async {
    final raw = await PluginFfi.invoke(
      initLuaPath: _init,
      actionId: _action,
      ctxJson: jsonEncode({
        'paths': paths,
        'dir': dir ?? tmp.path,
        'plugin_dir': p.dirname(_init),
        'form': ?form,
        'location': ?location,
      }),
    );
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    expect(json['ok'], isTrue, reason: '${json['error']}');

    return (json['effects'] as List).cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> dialogFields(List<Map<String, dynamic>> fx) {
    final dialog = fx.singleWhere((e) => e['type'] == 'dialog');

    return ((dialog['dialog'] as Map)['fields'] as List)
        .cast<Map<String, dynamic>>();
  }

  Future<String> suggestion(List<String> names) async {
    final fields = dialogFields(await invoke(files(names)));

    return fields.singleWhere((f) => f['id'] == 'name')['default'] as String;
  }

  test('registers a menubar entry and a selection context entry', () async {
    final json =
        jsonDecode((await PluginFfi.load(_init))!) as Map<String, dynamic>;
    final byMenu = {
      for (final c in (json['contributions'] as List).cast<Map>()) c['menu']: c,
    };
    expect(byMenu.keys, containsAll(<String>['menubar', 'context']));
    expect(byMenu['context']!['where'], ['selection']);
  });

  test('suggests the stem of the first marked item', () async {
    expect(
      await suggestion(['IMG_2026_0102.jpg', 'IMG_2026_0101.jpg']),
      'IMG_2026_0102',
    );
  });

  test('suggests the stem of a single item', () async {
    expect(await suggestion(['memo.txt']), 'memo');
    expect(await suggestion(['実験データ.tar.gz']), '実験データ.tar');
    expect(await suggestion(['README']), 'README');
  });

  test('keeps the dot of a folder name', () async {
    Directory(p.join(tmp.path, 'v1.2')).createSync();
    final fields = dialogFields(await invoke([p.join(tmp.path, 'v1.2')]));
    expect(fields.singleWhere((f) => f['id'] == 'name')['default'], 'v1.2');
  });

  test('re-asks with an error when a file has the name', () async {
    final paths = files(['a.txt', 'b.txt', 'taken']);
    final fx = await invoke(paths.take(2).toList(), form: {'name': 'taken'});
    final fields = dialogFields(fx);
    expect(fields.first['type'], 'info');
    expect(fields.first['label'], contains('A file named taken'));
    expect(fields.last['default'], 'taken');
    expect(fields.any((f) => f['id'] == 'merge'), isFalse);
    expect(fx.where((e) => e['type'] == 'operation'), isEmpty);
  });

  test('asks before adding to an existing folder', () async {
    final paths = files(['a.txt', 'b.txt']);
    Directory(p.join(tmp.path, 'sorted')).createSync();
    final fx = await invoke(paths, form: {'name': 'sorted'});
    final fields = dialogFields(fx);
    expect(fields.first['label'], contains('sorted already exists'));
    final merge = fields.singleWhere((f) => f['id'] == 'merge');
    expect(merge['type'], 'checkbox');
    expect(merge['default'], isTrue);
    expect(merge['label'], contains('2 item(s)'));
    expect(fx.where((e) => e['type'] == 'operation'), isEmpty);
  });

  test('re-asks when adding to an existing folder is unchecked', () async {
    final paths = files(['a.txt']);
    Directory(p.join(tmp.path, 'sorted')).createSync();
    final fx = await invoke(paths, form: {'name': 'sorted', 'merge': false});
    expect(dialogFields(fx).any((f) => f['id'] == 'merge'), isTrue);
    expect(fx.where((e) => e['type'] == 'operation'), isEmpty);
  });

  test('moves into the existing folder once confirmed', () async {
    final paths = files(['a.txt', 'b.txt']);
    final existing = Directory(p.join(tmp.path, 'Sorted'))..createSync();
    File(p.join(existing.path, 'keep.txt')).writeAsStringSync('k');
    final name = Platform.isWindows ? 'sorted' : 'Sorted';
    final fx = await invoke(paths, form: {'name': name, 'merge': true});
    final ops = fx.where((e) => e['type'] == 'operation').toList();
    expect(ops.map((e) => e['src']), paths);
    expect(ops.map((e) => e['dst']).toSet(), {existing.path});
    expect(File(p.join(existing.path, 'keep.txt')).existsSync(), isTrue);
  });

  test('re-asks when the name is one of the moved items', () async {
    final paths = files(['a.txt', 'b.txt']);
    final fx = await invoke(paths, form: {'name': 'a.txt'});
    expect(dialogFields(fx).first['label'], contains('being moved'));
  });

  test('re-asks on an empty name or a path separator', () async {
    final paths = files(['a.txt']);
    expect(
      dialogFields(await invoke(paths, form: {'name': ''})).first['label'],
      contains('Enter a folder name'),
    );
    expect(
      dialogFields(await invoke(paths, form: {'name': 'x/y'})).first['label'],
      contains('path separator'),
    );
  });

  test('creates the folder and queues the moves in order', () async {
    final paths = files(['b.txt', 'a.txt']);
    final fx = await invoke(paths, form: {'name': 'sorted'});
    final folder = p.join(tmp.path, 'sorted');
    expect(Directory(folder).existsSync(), isTrue);
    final ops = fx.where((e) => e['type'] == 'operation').toList();
    expect(ops.map((e) => e['op']), ['move', 'move']);
    expect(ops.map((e) => e['src']), paths);
    expect(ops.map((e) => e['dst']).toSet(), {folder});
    expect(fx.last, {'type': 'focus', 'path': folder});
  });

  test('refuses a non-local location reported by the host', () async {
    final fx = await invoke(
      files(['a.txt']),
      location: {'scheme': 'archive', 'is_local': false},
    );
    expect(fx.singleWhere((e) => e['type'] == 'notify')['level'], 'warn');
    expect(fx.where((e) => e['type'] == 'dialog'), isEmpty);
  });

  test('pre-selects the suggested name', () async {
    final fields = dialogFields(await invoke(files(['memo.txt'])));
    expect(fields.singleWhere((f) => f['id'] == 'name')['select'], 'all');
  });

  test('refuses a folder that cannot be listed', () async {
    final fx = await invoke(['sftp://host/x/a.txt'], dir: 'sftp://host/x');
    final notify = fx.singleWhere((e) => e['type'] == 'notify');
    expect(notify['level'], 'warn');
    expect(fx.where((e) => e['type'] == 'dialog'), isEmpty);
  });
}
