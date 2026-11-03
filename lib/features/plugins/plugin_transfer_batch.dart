import 'plugin_models.dart';

const _batchedOps = {'copy', 'move'};

List<PluginEffect> batchPluginTransfers(List<PluginEffect> effects) {
  final out = <PluginEffect>[];
  for (final effect in effects) {
    final op = effect.data['op'];
    final src = effect.data['src'];
    final dst = effect.data['dst'];
    if (effect.type != 'operation' ||
        !_batchedOps.contains(op) ||
        src is! String ||
        dst is! String) {
      out.add(effect);
      continue;
    }
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        last.type == 'operation' &&
        last.data['op'] == op &&
        last.data['dst'] == dst &&
        last.data['srcs'] is List<String>) {
      (last.data['srcs'] as List<String>).add(src);
      continue;
    }
    out.add(
      PluginEffect('operation', {
        'op': op,
        'srcs': <String>[src],
        'dst': dst,
      }),
    );
  }

  return out;
}
