import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/platform/trash_location.dart';
import 'package:waydir/features/plugins/plugin_location.dart';
import 'package:waydir/features/tags/tag_path.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('waydir_ploc_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a plain folder is local', () {
    expect(pluginLocation(tmp.path), {'scheme': 'file', 'is_local': true});
  });

  test('remote and virtual locations are not local', () {
    expect(pluginLocation('sftp://host/home/u'), {
      'scheme': 'sftp',
      'is_local': false,
    });
    expect(pluginLocation('smb://host/share'), {
      'scheme': 'smb',
      'is_local': false,
    });
    expect(pluginLocation(kTrashPath)['scheme'], 'trash');
    expect(pluginLocation(tagPathFor(3))['scheme'], 'tag');
  });

  test('an archive reports its file and inner path', () {
    final zip = File(p.join(tmp.path, 'a.zip'))..writeAsBytesSync([0]);
    final root = pluginLocation(zip.path);
    expect(root['scheme'], 'archive');
    expect(root['is_local'], isFalse);
    expect(root['archive'], zip.path);
    expect(root['inner'], '');
    final inner = pluginLocation(p.join(zip.path, 'docs', 'x'));
    expect(inner['archive'], zip.path);
    expect(inner['inner'], isNotEmpty);
  });
}
