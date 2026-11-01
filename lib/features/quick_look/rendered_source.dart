import 'package:signals/signals.dart';

import '../../core/models/file_entry.dart';
import 'generators/generator_registry.dart';
import 'quick_look_common.dart';
import 'quick_look_io.dart';

class RenderedSource {
  RenderedSource._();

  static const _maxCached = 512;
  static final _textByKey = signal<Map<String, bool>>({});
  static final _inFlight = <String>{};

  static Future<Probe> Function(FileEntry entry) probe = probeFile;

  static bool available(FileEntry entry) {
    if (entry.type == FileItemType.folder) return false;
    final ext = entry.extension;
    if (GeneratorRegistry.instance.forExtension(ext) == null) {
      return markdownExts.contains(ext);
    }
    final key = '${entry.realPath}|${entry.modifiedMs}|${entry.size}';
    final known = _textByKey.value[key];
    if (known != null) return known;
    if (_inFlight.add(key)) _resolve(entry, key);

    return false;
  }

  static Future<void> _resolve(FileEntry entry, String key) async {
    var isText = false;
    try {
      isText = (await probe(entry)).kind == QlKind.text;
    } catch (_) {}
    _inFlight.remove(key);
    final current = _textByKey.value;
    _textByKey.value = {
      if (current.length < _maxCached) ...current,
      key: isText,
    };
  }

  static void reset() {
    _inFlight.clear();
    _textByKey.value = {};
  }
}
