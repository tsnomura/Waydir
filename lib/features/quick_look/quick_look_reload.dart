import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/app_theme.dart';
import 'code_editor.dart';

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
  int _suspended = 0;
  int _epoch = 0;

  String? get path => _path;

  void start(String path) {
    if (_path == path) return;
    _timer?.cancel();
    _path = path;
    _modifiedMs = null;
    _size = null;
    _ticking = false;
    _epoch++;
    _timer = Timer.periodic(interval, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _path = null;
    _modifiedMs = null;
    _size = null;
    _epoch++;
  }

  void suspend() {
    _suspended++;
    _epoch++;
  }

  Future<FileStat?> resume() async {
    final path = _path;
    try {
      if (path == null) return null;
      final stat = await File(path).stat();
      if (_path != path || stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      _modifiedMs = stat.modified.millisecondsSinceEpoch;
      _size = stat.size;

      return stat;
    } finally {
      if (_suspended > 0) _suspended--;
      _epoch++;
    }
  }

  Future<void> _tick() async {
    if (_ticking || _suspended > 0) return;
    _ticking = true;
    try {
      final path = _path;
      if (path == null) return;
      final epoch = _epoch;
      final stat = await File(path).stat();
      if (_path != path || epoch != _epoch) return;
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

class QuickLookReloadController {
  QuickLookReloadController({
    required this.editorController,
    required this.onReloadSkipped,
    Duration interval = const Duration(seconds: 1),
  }) {
    _watcher = FileChangeWatcher(interval: interval, onChanged: _onDiskChanged);
    editorController.writeGuard = _guardWrite;
  }

  final CodeEditorController editorController;
  final VoidCallback onReloadSkipped;
  final revision = signal(0);
  late final FileChangeWatcher _watcher;
  FileEntry? _entry;
  FileEntry? _stats;
  int _generation = 0;
  bool _disposed = false;

  int get generation => _generation;

  static bool canReload(FileEntry? entry) =>
      entry != null &&
      entry.type == FileItemType.file &&
      !PlatformPaths.isRemoteUri(entry.realPath);

  void watch(FileEntry? entry) {
    if (entry == null || !canReload(entry)) {
      _entry = null;
      _stats = null;
      _watcher.stop();

      return;
    }
    if (_entry?.realPath != entry.realPath) _stats = null;
    _entry = entry;
    _watcher.start(entry.realPath);
  }

  FileEntry? shown(FileEntry? entry) {
    final stats = _stats;
    if (entry == null || stats == null) return entry;

    return stats.realPath == entry.realPath ? stats : entry;
  }

  Future<void> request(BuildContext context) async {
    final entry = _entry;
    if (entry == null) return;
    if (editorController.dirty.value) {
      final choice = await confirmUnsavedChanges(
        context,
        t.quickLook.reloadMessage,
      );
      if (choice == UnsavedChoice.cancel) return;
      if (choice == UnsavedChoice.save) {
        await editorController.save();

        return;
      }
    }
    final stat = await File(entry.realPath).stat();
    if (_disposed || _entry?.realPath != entry.realPath) return;
    if (stat.type == FileSystemEntityType.notFound) return;
    _apply(entry, stat, reload: true);
  }

  void dispose() {
    _disposed = true;
    _watcher.stop();
    if (editorController.writeGuard == _guardWrite) {
      editorController.writeGuard = null;
    }
    revision.dispose();
  }

  void _onDiskChanged(String path, int modifiedMs, int size) {
    final entry = _entry;
    if (_disposed || entry == null || entry.realPath != path) return;
    if (editorController.dirty.value) {
      onReloadSkipped();

      return;
    }
    _stats = entry.copyWithStats(size: size, modifiedMs: modifiedMs);
    _reload(entry);
  }

  void _apply(FileEntry entry, FileStat stat, {required bool reload}) {
    _stats = entry.copyWithStats(
      size: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    );
    if (reload) {
      _reload(entry);
    } else {
      revision.value++;
    }
  }

  void _reload(FileEntry entry) {
    evictPreviewImage(entry.realPath);
    _generation++;
    revision.value++;
  }

  Future<void> _guardWrite(Future<void> Function() write) async {
    _watcher.suspend();
    try {
      await write();
    } finally {
      final stat = await _watcher.resume();
      final entry = _entry;
      if (!_disposed &&
          stat != null &&
          entry != null &&
          _watcher.path == entry.realPath) {
        _apply(entry, stat, reload: false);
      }
    }
  }
}

enum UnsavedChoice { cancel, discard, save }

Future<UnsavedChoice> confirmUnsavedChanges(
  BuildContext context,
  String message,
) async {
  final result = await showCustomDialog<String>(
    context: context,
    title: t.quickLook.unsavedTitle,
    icon: WaydirIconsRegular.warning,
    iconColor: AppColors.warning,
    body: Text(message, style: context.txt.row.copyWith(color: AppColors.fg)),
    actions: [
      DialogAction(label: t.quickLook.cancel, color: AppColors.fgMuted),
      DialogAction(label: t.quickLook.discard, color: AppColors.danger),
      DialogAction(label: t.quickLook.save, color: AppColors.accent),
    ],
  );
  if (!context.mounted || result == null || result == t.quickLook.cancel) {
    return UnsavedChoice.cancel;
  }

  return result == t.quickLook.save
      ? UnsavedChoice.save
      : UnsavedChoice.discard;
}

void evictPreviewImage(String path) {
  PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
}
