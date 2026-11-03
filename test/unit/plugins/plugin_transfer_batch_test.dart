import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/plugins/plugin_models.dart';
import 'package:waydir/features/plugins/plugin_transfer_batch.dart';

PluginEffect op(String kind, String src, String dst) =>
    PluginEffect('operation', {'op': kind, 'src': src, 'dst': dst});

void main() {
  test('merges consecutive moves to the same destination in order', () {
    final out = batchPluginTransfers([
      op('move', '/a/1', '/a/new'),
      op('move', '/a/2', '/a/new'),
      op('move', '/a/3', '/a/new'),
      const PluginEffect('refresh', {}),
    ]);
    expect(out, hasLength(2));
    expect(out[0].data, {
      'op': 'move',
      'srcs': ['/a/1', '/a/2', '/a/3'],
      'dst': '/a/new',
    });
    expect(out[1].type, 'refresh');
  });

  test('splits on a different destination, kind or effect in between', () {
    final out = batchPluginTransfers([
      op('move', '/a/1', '/x'),
      op('move', '/a/2', '/y'),
      op('copy', '/a/3', '/y'),
      const PluginEffect('toast', {'message': 'hi'}),
      op('copy', '/a/4', '/y'),
    ]);
    expect(out.map((e) => e.data['srcs']), [
      ['/a/1'],
      ['/a/2'],
      ['/a/3'],
      null,
      ['/a/4'],
    ]);
  });

  test('leaves delete and trash one per path', () {
    final out = batchPluginTransfers([
      PluginEffect('operation', {'op': 'delete', 'src': '/a/1'}),
      PluginEffect('operation', {'op': 'delete', 'src': '/a/2'}),
      PluginEffect('operation', {'op': 'trash', 'src': '/a/3'}),
    ]);
    expect(out, hasLength(3));
    expect(out.map((e) => e.data['src']), ['/a/1', '/a/2', '/a/3']);
    expect(out.every((e) => !e.data.containsKey('srcs')), isTrue);
  });

  test('passes malformed transfers through untouched', () {
    final bad = PluginEffect('operation', {'op': 'move', 'src': '/a/1'});
    expect(batchPluginTransfers([bad]).single, same(bad));
  });
}
