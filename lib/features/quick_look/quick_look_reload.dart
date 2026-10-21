import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

class FileChangeWatcher {
  FileChangeWatcher({
    this.interval = const Duration(seconds: 1),
    required this.onChanged,
  });

  final Duration interval;
  final void Function(String path, int modifiedMs, int size) onChanged;

  Timer? _timer;
  String? _path;
  int? _modifiedMs;
  int? _size;
  bool _ticking = false;

  String? get path => _path;

  void start(String path) {
    if (_path == path) return;
    _timer?.cancel();
    _path = path;
    _modifiedMs = null;
    _size = null;
    _ticking = false;
    _timer = Timer.periodic(interval, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _path = null;
    _modifiedMs = null;
    _size = null;
  }

  void refreshBaseline(int modifiedMs, int size) {
    if (_path == null) return;
    _modifiedMs = modifiedMs;
    _size = size;
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final path = _path;
      if (path == null) return;
      final stat = await File(path).stat();
      if (_path != path) return;
      if (stat.type == FileSystemEntityType.notFound) return;
      final modifiedMs = stat.modified.millisecondsSinceEpoch;
      final size = stat.size;
      final knownMs = _modifiedMs;
      final knownSize = _size;
      _modifiedMs = modifiedMs;
      _size = size;
      if (knownMs == null || (modifiedMs == knownMs && size == knownSize)) {
        return;
      }
      onChanged(path, modifiedMs, size);
    } finally {
      _ticking = false;
    }
  }
}

void evictPreviewImage(String path) {
  PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
}
