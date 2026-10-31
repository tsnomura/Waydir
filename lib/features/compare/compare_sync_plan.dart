import 'package:path/path.dart' as p;

import '../../core/models/file_entry.dart';
import 'compare_diff.dart';

class CompareSyncPlan {
  final String sourceRoot;
  final String destinationRoot;
  final Map<String, List<String>> groups;
  final Set<String> overwrites;
  final List<CompareEntryResult> added;
  final List<CompareEntryResult> updated;
  final List<CompareEntryResult> differing;
  final List<CompareEntryResult> skipped;

  const CompareSyncPlan({
    required this.sourceRoot,
    required this.destinationRoot,
    required this.groups,
    required this.overwrites,
    required this.added,
    required this.updated,
    required this.differing,
    required this.skipped,
  });

  bool get isEmpty => groups.isEmpty;

  int get addedFiles =>
      added.where((r) => r.type != FileItemType.folder).length;

  int get addedFolders => added.length - addedFiles;

  int get addedBytes => _bytes(added);

  int get updatedBytes => _bytes(updated);

  int get differingBytes => _bytes(differing);

  int get totalBytes => addedBytes + updatedBytes + differingBytes;

  List<CompareEntryResult> get items =>
      [...added, ...updated, ...differing]
        ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

  static int _bytes(List<CompareEntryResult> results) => results
      .where((r) => r.type != FileItemType.folder)
      .fold(0, (sum, r) => sum + r.entry.size);
}

CompareSyncPlan buildCompareSyncPlan({
  required String sourceRoot,
  required String destinationRoot,
  required Iterable<CompareEntryResult> sourceResults,
  Set<String> scope = const {},
}) {
  bool inScope(CompareEntryResult result) {
    if (scope.isEmpty) return true;

    return scope.any(
      (rel) =>
          result.relativePath == rel || result.relativePath.startsWith('$rel/'),
    );
  }

  final scoped = sourceResults.where(inScope).toList()
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  final candidates = scoped.where(_shouldSync).toList();
  final filtered = <CompareEntryResult>[];
  for (final candidate in candidates) {
    final nested = filtered.any(
      (existing) =>
          existing.type == FileItemType.folder &&
          candidate.relativePath.startsWith('${existing.relativePath}/'),
    );
    if (!nested) filtered.add(candidate);
  }
  final groups = <String, List<String>>{};
  for (final entry in filtered) {
    final destination = compareSyncDestinationFor(
      destinationRoot,
      entry.relativePath,
    );
    (groups[destination] ??= <String>[]).add(entry.path);
  }

  return CompareSyncPlan(
    sourceRoot: sourceRoot,
    destinationRoot: destinationRoot,
    groups: groups,
    overwrites: {
      for (final entry in filtered)
        if (entry.status != CompareStatus.unique) entry.path,
    },
    added: [
      for (final r in candidates)
        if (r.status == CompareStatus.unique) r,
    ],
    updated: [
      for (final r in candidates)
        if (r.status == CompareStatus.newer) r,
    ],
    differing: [
      for (final r in candidates)
        if (r.status == CompareStatus.differ) r,
    ],
    skipped: [
      for (final r in scoped)
        if (r.status == CompareStatus.older && r.type == FileItemType.file) r,
    ],
  );
}

bool _shouldSync(CompareEntryResult result) {
  return switch (result.status) {
    CompareStatus.unique => true,
    CompareStatus.newer => result.type == FileItemType.file,
    CompareStatus.differ => result.type == FileItemType.file,
    CompareStatus.older ||
    CompareStatus.identical ||
    CompareStatus.pending => false,
  };
}

String compareSyncDestinationFor(String destinationRoot, String relativePath) {
  final dir = p.posix.dirname(relativePath);
  if (dir == '.') return destinationRoot;

  return p.joinAll([destinationRoot, ...dir.split('/')]);
}
