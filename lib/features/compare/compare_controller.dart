import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';

import '../../core/fs/file_system_service.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../ui/theme/app_theme.dart';
import '../files/row_decorations.dart';
import '../navigation/navigation_store.dart';
import '../operations/operation_store.dart';
import '../panes/pane_store.dart';
import 'compare_diff.dart';

class CompareController {
  final Signal<List<PaneStore>> panes;
  final Signal<bool> isDual;
  final OperationStore operationStore;
  final ReadonlySignal<int>? activePaneIndex;

  final active = signal(false);
  final running = signal(false);
  final recursive = signal(true);
  final leftResults = signal<Map<String, CompareEntryResult>>({});
  final rightResults = signal<Map<String, CompareEntryResult>>({});
  final counts = signal(const CompareCounts());

  int _runId = 0;
  void Function()? _taskDisposer;
  void Function()? _scopeDisposer;
  void Function()? _ghostDisposer;
  final _followDisposers = <void Function()>[];
  final _linked = signal<(NavigationStore, NavigationStore)?>(null);
  String? _leftRoot;
  String? _rightRoot;
  NavigationStore? _leftDecorated;
  NavigationStore? _rightDecorated;

  CompareController({
    required this.panes,
    required this.isDual,
    required this.operationStore,
    this.activePaneIndex,
  }) {
    _taskDisposer = effect(() {
      final completed = operationStore.taskCompleted.value;
      if (completed == null || !active.value) return;
      scheduleMicrotask(start);
    });
    _scopeDisposer = effect(() {
      if (!active.value) return;
      final pair = _activeStores();
      final leftRoot = _leftRoot;
      final rightRoot = _rightRoot;
      if (pair == null || leftRoot == null || rightRoot == null) {
        scheduleMicrotask(stop);

        return;
      }
      final leftPath = pair.$1.currentPath.value;
      final rightPath = pair.$2.currentPath.value;
      if (!_withinScope(leftRoot, leftPath) ||
          !_withinScope(rightRoot, rightPath)) {
        scheduleMicrotask(stop);
      }
    });
    _ghostDisposer = effect(() {
      final leftRes = leftResults.value;
      final rightRes = rightResults.value;
      final leftStore = _leftDecorated;
      final rightStore = _rightDecorated;
      final leftRoot = _leftRoot;
      final rightRoot = _rightRoot;
      if (leftStore == null ||
          rightStore == null ||
          leftRoot == null ||
          rightRoot == null) {
        return;
      }
      final leftGhosts = _ghostsFor(
        leftRoot,
        leftStore.currentPath.value,
        rightRes,
      );
      final rightGhosts = _ghostsFor(
        rightRoot,
        rightStore.currentPath.value,
        leftRes,
      );
      untracked(() {
        leftStore.ghostFiles.value = leftGhosts;
        rightStore.ghostFiles.value = rightGhosts;
      });
    });
    _setupFollow(leftLeads: true);
    _setupFollow(leftLeads: false);
  }

  void _setupFollow({required bool leftLeads}) {
    (NavigationStore, NavigationStore)? ordered() {
      final pair = _linked.value;
      if (pair == null) return null;

      return leftLeads ? pair : (pair.$2, pair.$1);
    }

    _followDisposers.add(
      _skipFirst(leftLeads, () {
        final pair = ordered();
        if (pair == null) return null;
        final offset = pair.$1.scrollLink.reported.value;

        return () => pair.$2.scrollLink.request(offset);
      }),
    );
    _followDisposers.add(
      _skipFirst(leftLeads, () {
        final pair = ordered();
        if (pair == null) return null;
        final name = pair.$1.cursorEntry.value?.name;
        if (name == null || !_sameRelativeFolder(leftLeads, pair)) return null;

        return () => pair.$2.moveCursorToName(name);
      }),
    );
    _followDisposers.add(
      _skipFirst(leftLeads, () {
        final pair = ordered();
        if (pair == null) return null;
        final path = pair.$1.currentPath.value;

        return () => _followFolder(leftLeads, path, pair.$2);
      }),
    );
  }

  void Function() _skipFirst(bool runFirst, void Function()? Function() track) {
    (NavigationStore, NavigationStore)? seenPair;

    return effect(() {
      final action = track();
      final pair = _linked.value;
      final fresh = !identical(pair, seenPair);
      seenPair = pair;
      if (action == null || (fresh && !runFirst)) return;
      untracked(action);
    });
  }

  String? _relativeIn(String? root, String path) {
    if (root == null) return null;
    if (path != root && !p.isWithin(root, path)) return null;

    return compareRelativePath(root, path);
  }

  bool _sameRelativeFolder(
    bool leftLeads,
    (NavigationStore, NavigationStore) pair,
  ) {
    final leaderRoot = leftLeads ? _leftRoot : _rightRoot;
    final followerRoot = leftLeads ? _rightRoot : _leftRoot;
    final a = _relativeIn(leaderRoot, pair.$1.currentPath.value);
    final b = _relativeIn(followerRoot, pair.$2.currentPath.value);

    return a != null && a == b;
  }

  void _followFolder(bool leftLeads, String leaderPath, NavigationStore to) {
    final leaderRoot = leftLeads ? _leftRoot : _rightRoot;
    final followerRoot = leftLeads ? _rightRoot : _leftRoot;
    if (followerRoot == null) return;
    final rel = _relativeIn(leaderRoot, leaderPath);
    if (rel == null) return;
    final target = rel.isEmpty
        ? followerRoot
        : rel.split('/').fold(followerRoot, PlatformPaths.join);
    if (to.currentPath.value == target) return;
    if (rel.isNotEmpty) {
      final results = leftLeads ? rightResults.value : leftResults.value;
      final exists = results.values.any(
        (r) => r.relativePath == rel && r.type == FileItemType.folder,
      );
      if (!exists) return;
    }
    to.navigateTo(target);
  }

  List<FileEntry> _ghostsFor(
    String root,
    String dir,
    Map<String, CompareEntryResult> other,
  ) {
    if (other.isEmpty || !_withinScope(root, dir)) return const [];
    final rel = compareRelativePath(root, dir);
    final out = <FileEntry>[];
    for (final result in other.values) {
      if (result.status != CompareStatus.unique) continue;
      final parent = p.posix.dirname(result.relativePath);
      if ((parent == '.' ? '' : parent) != rel) continue;
      final source = result.entry;
      out.add(
        FileEntry.raw(
          name: source.name,
          path: PlatformPaths.join(dir, source.name),
          type: source.type,
          size: source.size,
          modifiedMs: source.modifiedMs,
          createdMs: source.createdMs,
          addedMs: source.addedMs,
          ghostOf: source,
        ),
      );
    }

    return out;
  }

  bool _withinScope(String root, String path) {
    if (path == root) return true;
    if (!recursive.value) return false;

    return p.isWithin(root, path);
  }

  bool get canStart {
    final pair = _activeStores();
    if (pair == null) return false;

    return _isComparablePath(pair.$1.currentPath.value) &&
        _isComparablePath(pair.$2.currentPath.value);
  }

  Future<void> toggle() async {
    if (active.value) {
      stop();
    } else {
      await start();
    }
  }

  Future<void> start() async {
    if (!canStart) return;
    final pair = _activeStores();
    if (pair == null) return;
    final run = ++_runId;
    final leftStore = pair.$1;
    final rightStore = pair.$2;
    final leftRoot = leftStore.currentPath.value;
    final rightRoot = rightStore.currentPath.value;
    if (!active.value &&
        (PlatformPaths.isNetworkPath(leftRoot) ||
            PlatformPaths.isNetworkPath(rightRoot))) {
      this.recursive.value = false;
    }
    _leftRoot = leftRoot;
    _rightRoot = rightRoot;
    running.value = true;
    active.value = true;
    final recursive = this.recursive.value;
    try {
      final listed = await Future.wait([
        _entriesFor(leftRoot, run, recursive),
        _entriesFor(rightRoot, run, recursive),
      ]);
      if (run != _runId) return;
      final contentEqual = await _contentEqual(
        leftRoot,
        rightRoot,
        listed[0],
        listed[1],
        run,
      );
      if (run != _runId) return;
      final diff = buildCompareDiff(
        leftRoot: leftRoot,
        rightRoot: rightRoot,
        leftEntries: listed[0],
        rightEntries: listed[1],
        contentEqual: contentEqual,
      );
      batch(() {
        _clearDecorations();
        _leftDecorated = leftStore;
        _rightDecorated = rightStore;
        leftResults.value = diff.left;
        rightResults.value = diff.right;
        counts.value = diff.counts;
        rightStore.sortLeader.value = leftStore;
        final linked = _linked.value;
        if (linked == null ||
            !identical(linked.$1, leftStore) ||
            !identical(linked.$2, rightStore)) {
          _linked.value = (leftStore, rightStore);
        }
        leftStore.decorations.setLayer('compare', _decorationsFor(diff.left));
        rightStore.decorations.setLayer('compare', _decorationsFor(diff.right));
      });
    } finally {
      if (run == _runId) running.value = false;
    }
  }

  (FileEntry, FileEntry)? diffPairFor(String path) {
    if (!active.value) return null;
    final left = leftResults.value;
    final right = rightResults.value;
    final fromLeft = left[path];
    final source = fromLeft ?? right[path];
    if (source == null || source.type != FileItemType.file) return null;
    final others = fromLeft != null ? right : left;
    CompareEntryResult? match;
    for (final candidate in others.values) {
      if (candidate.relativePath == source.relativePath) {
        match = candidate;
        break;
      }
    }
    if (match == null || match.type != FileItemType.file) return null;

    return fromLeft != null
        ? (source.entry, match.entry)
        : (match.entry, source.entry);
  }

  Future<void> syncLeftToRight() => _sync(leftToRight: true);

  Future<void> syncRightToLeft() => _sync(leftToRight: false);

  Future<void> setRecursive(bool value) async {
    if (recursive.value == value) return;
    recursive.value = value;
    if (active.value) await start();
  }

  void stop() {
    _runId++;
    running.value = false;
    active.value = false;
    leftResults.value = const {};
    rightResults.value = const {};
    counts.value = const CompareCounts();
    _leftRoot = null;
    _rightRoot = null;
    _linked.value = null;
    _clearDecorations();
  }

  void _clearDecorations() {
    _leftDecorated?.decorations.clearLayer('compare');
    _rightDecorated?.decorations.clearLayer('compare');
    _leftDecorated?.ghostFiles.value = const [];
    _rightDecorated?.ghostFiles.value = const [];
    _rightDecorated?.sortLeader.value = null;
    _leftDecorated = null;
    _rightDecorated = null;
  }

  void dispose() {
    _taskDisposer?.call();
    _taskDisposer = null;
    _scopeDisposer?.call();
    _scopeDisposer = null;
    _ghostDisposer?.call();
    _ghostDisposer = null;
    for (final dispose in _followDisposers) {
      dispose();
    }
    _followDisposers.clear();
    stop();
    active.dispose();
    running.dispose();
    recursive.dispose();
    leftResults.dispose();
    rightResults.dispose();
    counts.dispose();
  }

  (NavigationStore, NavigationStore)? _activeStores() {
    if (!isDual.value) return null;
    final list = panes.value;
    if (list.length < 2) return null;

    return (
      list[0].tabs.activeTab.value.store,
      list[1].tabs.activeTab.value.store,
    );
  }

  bool _isComparablePath(String path) {
    if (path.isEmpty) return false;
    // smb:// is a Linux gvfs mount alias resolved to a real local path
    // before any FS op reaches it (see LocationResolver) — not a backend
    // compare can talk to directly, unlike sftp://.
    if (PlatformPaths.isSmbUri(path)) return false;
    // sftp:// has no cheap synchronous existence check available (it's a
    // network round trip); trust that a pane already showing this path
    // means it was already proven to exist by successfully navigating
    // there.
    if (PlatformPaths.isSftpUri(path)) return true;
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<List<FileEntry>> _entriesFor(
    String root,
    int run,
    bool recursive,
  ) async {
    if (!recursive) return FileSystemService.listDirectory(root);
    if (!PlatformPaths.isRemoteUri(root)) {
      return FileSystemService.listRecursive(root);
    }

    return _walkPerDirectory(root, run);
  }

  Future<Set<String>> _contentEqual(
    String leftRoot,
    String rightRoot,
    List<FileEntry> leftEntries,
    List<FileEntry> rightEntries,
    int run,
  ) async {
    if (PlatformPaths.isNetworkPath(leftRoot) ||
        PlatformPaths.isNetworkPath(rightRoot)) {
      return const {};
    }
    final candidates = contentCheckCandidates(
      leftRoot: leftRoot,
      rightRoot: rightRoot,
      leftEntries: leftEntries,
      rightEntries: rightEntries,
    ).entries.toList();
    final out = <String>{};
    const chunk = 32;
    for (var i = 0; i < candidates.length; i += chunk) {
      if (run != _runId) return const {};
      final slice = candidates.sublist(
        i,
        i + chunk > candidates.length ? candidates.length : i + chunk,
      );
      final List<bool?> results;
      try {
        results = await FileSystemService.filesEqual([
          for (final c in slice) c.value,
        ]);
      } catch (_) {
        return out;
      }
      for (var j = 0; j < slice.length && j < results.length; j++) {
        if (results[j] == true) out.add(slice[j].key);
      }
    }

    return out;
  }

  Future<List<FileEntry>> _walkPerDirectory(String root, int run) async {
    final out = <FileEntry>[];
    final pending = <String>[root];
    final visited = <String>{root};
    while (pending.isNotEmpty) {
      if (run != _runId) return const [];
      final dir = pending.removeLast();
      final entries = await FileSystemService.listDirectory(dir);
      for (final entry in entries) {
        out.add(entry);
        if (entry.type == FileItemType.folder && visited.add(entry.path)) {
          pending.add(entry.path);
        }
      }
    }

    return out;
  }

  Map<String, RowDecoration> _decorationsFor(
    Map<String, CompareEntryResult> results,
  ) {
    final out = <String, RowDecoration>{};
    for (final entry in results.values) {
      final decoration = _decorationFor(entry.status);
      if (decoration == null) continue;
      out[entry.path] = decoration;
    }

    return out;
  }

  Future<void> _sync({required bool leftToRight}) async {
    if (!active.value) return;
    final pair = _activeStores();
    if (pair == null) return;
    final sourceStore = leftToRight ? pair.$1 : pair.$2;
    final destinationStore = leftToRight ? pair.$2 : pair.$1;
    final sourceResults = leftToRight ? leftResults.value : rightResults.value;
    final destinationRoot = destinationStore.currentPath.value;
    final selected = sourceStore.selectedPaths.value;
    final selectedRel = <String>{};
    for (final path in selected) {
      final result = sourceResults[path];
      if (result != null) selectedRel.add(result.relativePath);
    }
    final destinationIndex = leftToRight ? 1 : 0;
    final ghost = destinationStore.cursorEntry.value?.ghostOf;
    if (selectedRel.isEmpty &&
        ghost != null &&
        activePaneIndex?.value == destinationIndex) {
      final result = sourceResults[ghost.path];
      if (result != null) selectedRel.add(result.relativePath);
    }
    final candidates = sourceResults.values.where((result) {
      if (!_shouldSync(result)) return false;
      if (selectedRel.isEmpty) return true;

      return selectedRel.any(
        (rel) =>
            result.relativePath == rel ||
            result.relativePath.startsWith('$rel/'),
      );
    }).toList()..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final filtered = <CompareEntryResult>[];
    for (final candidate in candidates) {
      final nested = filtered.any(
        (existing) =>
            existing.type == FileItemType.folder &&
            candidate.relativePath.startsWith('${existing.relativePath}/'),
      );
      if (!nested) filtered.add(candidate);
    }
    final grouped = <String, List<String>>{};
    for (final entry in filtered) {
      final destination = destinationDirectoryFor(
        destinationRoot,
        entry.relativePath,
      );
      await FileSystemService.createDirectory(destination);
      (grouped[destination] ??= <String>[]).add(entry.path);
    }
    for (final group in grouped.entries) {
      operationStore.enqueueCopy(group.value, group.key);
    }
  }

  bool _shouldSync(CompareEntryResult result) {
    return switch (result.status) {
      CompareStatus.unique => true,
      CompareStatus.newer => result.type == FileItemType.file,
      CompareStatus.differ => result.type == FileItemType.file,
      CompareStatus.older || CompareStatus.identical => false,
    };
  }

  RowDecoration? _decorationFor(CompareStatus status) {
    return switch (status) {
      CompareStatus.unique => RowDecoration(
        tint: AppColors.compareUnique,
        badge: '+',
      ),
      CompareStatus.newer => RowDecoration(
        tint: AppColors.compareDiffer,
        badge: '↑',
      ),
      CompareStatus.older => RowDecoration(
        tint: AppColors.compareDiffer,
        badge: '↓',
      ),
      CompareStatus.differ => RowDecoration(
        tint: AppColors.compareDiffer,
        badge: '≠',
      ),
      CompareStatus.identical => null,
    };
  }

  String destinationDirectoryFor(String destinationRoot, String relativePath) {
    final dir = p.posix.dirname(relativePath);
    if (dir == '.') return destinationRoot;

    return p.joinAll([destinationRoot, ...dir.split('/')]);
  }
}
