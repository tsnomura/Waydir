import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:signals/signals.dart';

import '../../core/database/app_database.dart';
import '../../core/fs/file_system_service.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/platform_paths.dart';
import '../../core/settings/settings_store.dart';
import '../locations/location_resolver.dart';
import '../locations/location_uri.dart';

class BookmarkStore {
  static final BookmarkStore instance = BookmarkStore._();

  BookmarkStore._();

  final bookmarks = signal<List<Bookmark>>([]);
  final mounted = signal<Map<String, bool>>({});
  Timer? _mountTimer;
  Future<void>? _mountCheck;
  bool _checkAgain = false;

  AppDatabase get _db => SettingsStore.instance.db;

  Future<void> load() async {
    bookmarks.value = await _db.getBookmarks();
    _refreshMounted();
    _mountTimer ??= Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshMounted(),
    );
  }

  void _refreshMounted() {
    if (_mountCheck != null) {
      _checkAgain = true;

      return;
    }
    final paths = [
      for (final b in bookmarks.value)
        if (LocationUri.parse(b.path).isLocal) b.path,
    ];
    _mountCheck = _checkPaths(paths)
        .then((result) => mounted.value = result)
        .catchError((Object e, StackTrace st) {
          log.warn('bookmarks', 'mount check failed', error: e, stack: st);

          return mounted.value;
        })
        .whenComplete(() {
          _mountCheck = null;
          if (_checkAgain) {
            _checkAgain = false;
            _refreshMounted();
          }
        });
  }

  static Future<Map<String, bool>> _checkPaths(List<String> paths) =>
      Isolate.run(() => {for (final p in paths) p: _exists(p)});

  static bool _exists(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> addPath(String path) async {
    final storedPath = await _existingStoredPathFor(path);
    if (storedPath == null) return;
    final uri = LocationUri.parse(storedPath);
    final label = uri.isLocal
        ? PlatformPaths.fileName(storedPath)
        : uri.displayLabel;
    await _addUnique(label, storedPath);
  }

  bool containsPath(String path) {
    final storedPath = _storedPathFor(path);
    if (storedPath == null) return false;

    return bookmarks.value.any((b) => b.path == storedPath);
  }

  Future<void> togglePath(String path) async {
    final storedPath = await _existingStoredPathFor(path);
    if (storedPath == null) return;
    final existing = await _db.getBookmarkByPath(storedPath);
    if (existing != null) {
      await _db.deleteBookmark(existing.id);
      await load();

      return;
    }
    final uri = LocationUri.parse(storedPath);
    final label = uri.isLocal
        ? PlatformPaths.fileName(storedPath)
        : uri.displayLabel;
    await _addUnique(label, storedPath);
  }

  String? _storedPathFor(String path) {
    final uri = LocationUri.parse(path);
    if (!uri.isLocal) return uri.raw;
    final normalized = PlatformPaths.normalize(path);

    return LocationResolver.physicalToLogical(normalized) ?? normalized;
  }

  Future<String?> _existingStoredPathFor(String path) async {
    final stored = _storedPathFor(path);
    if (stored == null || !LocationUri.parse(stored).isLocal) return stored;
    if (stored != PlatformPaths.normalize(path)) return stored;

    return await FileSystemService.directoryExists(stored) ? stored : null;
  }

  Future<void> addLocation(String location, {String? label}) async {
    final uri = LocationUri.parse(location);
    final stored = uri.isLocal ? PlatformPaths.normalize(uri.raw) : uri.raw;
    final lbl = (label != null && label.trim().isNotEmpty)
        ? label.trim()
        : (uri.isLocal ? PlatformPaths.fileName(stored) : uri.displayLabel);
    await _addUnique(lbl, stored);
  }

  Future<void> _addUnique(String label, String storedPath) async {
    final existing = await _db.getBookmarkByPath(storedPath);
    if (existing != null) return;
    await _db.addBookmark(label, storedPath);
    await load();
  }

  Future<void> rename(Bookmark bookmark, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == bookmark.label) return;
    await _db.renameBookmark(bookmark.id, trimmed);
    await load();
  }

  Future<void> remove(Bookmark bookmark) async {
    await _db.deleteBookmark(bookmark.id);
    await load();
  }

  /// [newIndex] is the post-removal target index, as supplied by
  /// `ReorderableListView.onReorderItem`.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...bookmarks.value];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var to = newIndex;
    if (to < 0) to = 0;
    if (to > list.length - 1) to = list.length - 1;
    if (to == oldIndex) return;
    final item = list.removeAt(oldIndex);
    list.insert(to, item);
    bookmarks.value = list;
    await _db.reorderBookmarks(list.map((b) => b.id).toList());
  }
}
