part of '../file_view.dart';

/// Optional, user-toggleable file-list columns (Name and the recursive-search
/// Location column are not part of this set). Order here is the display order.
enum FileColumn { size, date, kind, created, added, permissions, owner }

String fileColumnLabel(FileColumn col) {
  final c = t.fileView.columns;
  switch (col) {
    case FileColumn.size:
      return c.size;
    case FileColumn.date:
      return c.dateModified;
    case FileColumn.kind:
      return c.kind;
    case FileColumn.created:
      return c.dateCreated;
    case FileColumn.added:
      return c.dateAdded;
    case FileColumn.permissions:
      return c.permissions;
    case FileColumn.owner:
      return c.owner;
  }
}

SortKey fileColumnSortKey(FileColumn col) {
  switch (col) {
    case FileColumn.size:
      return SortKey.size;
    case FileColumn.date:
      return SortKey.date;
    case FileColumn.kind:
      return SortKey.kind;
    case FileColumn.created:
      return SortKey.created;
    case FileColumn.added:
      return SortKey.added;
    case FileColumn.permissions:
      return SortKey.permissions;
    case FileColumn.owner:
      return SortKey.owner;
  }
}

String fileColumnText(
  FileColumn col,
  FileEntry e, {
  required String dateFmt,
  required bool recentDatesRelative,
  int? folderSize,
}) {
  final isFolder = e.type == FileItemType.folder;
  switch (col) {
    case FileColumn.size:
      if (isFolder) return folderSize == null ? '--' : formatBytes(folderSize);

      return formatBytes(e.size);
    case FileColumn.date:
      return _formatDateBy(
        e.modified,
        dateFmt,
        recentDatesRelative: recentDatesRelative,
      );
    case FileColumn.kind:
      return e.kind;
    case FileColumn.created:
      return _formatDateBy(
        e.created,
        dateFmt,
        recentDatesRelative: recentDatesRelative,
      );
    case FileColumn.added:
      return _formatDateBy(
        e.added,
        dateFmt,
        recentDatesRelative: recentDatesRelative,
      );
    case FileColumn.permissions:
      return e.permissionsString;
    case FileColumn.owner:
      return e.ownerName;
  }
}

Signal<bool> fileColumnSignal(FileColumn col) {
  final s = SettingsStore.instance;
  switch (col) {
    case FileColumn.size:
      return s.showColumnSize;
    case FileColumn.date:
      return s.showColumnDate;
    case FileColumn.kind:
      return s.showColumnKind;
    case FileColumn.created:
      return s.showColumnCreated;
    case FileColumn.added:
      return s.showColumnAdded;
    case FileColumn.permissions:
      return s.showColumnPermissions;
    case FileColumn.owner:
      return s.showColumnOwner;
  }
}

/// Parses the saved column order (a CSV of [FileColumn] names) into the full
/// ordered list. Unknown ids are dropped and any column missing from the saved
/// string is appended in declaration order, so newly added columns always show.
List<FileColumn> parseColumnOrder(String csv) {
  final byName = {for (final c in FileColumn.values) c.name: c};
  final out = <FileColumn>[];
  for (final id in csv.split(',')) {
    final col = byName[id.trim()];
    if (col != null && !out.contains(col)) out.add(col);
  }
  for (final c in FileColumn.values) {
    if (!out.contains(c)) out.add(c);
  }

  return out;
}

String columnOrderToString(List<FileColumn> columns) =>
    columns.map((c) => c.name).join(',');

/// Whether [col] is meaningful on the current platform. Permissions and owner
/// are POSIX concepts that Windows doesn't expose, so they're hidden there.
/// Date added relies on kMDItemDateAdded (macOS xattr) and is macOS-only.
bool columnAvailable(FileColumn col) {
  if (PlatformPaths.isWindows &&
      (col == FileColumn.permissions || col == FileColumn.owner)) {
    return false;
  }

  if (col == FileColumn.added && !PlatformPaths.isMacOS) {
    return false;
  }

  return true;
}

/// All optional columns in the user-defined display order.
List<FileColumn> orderedColumns() => [
  for (final col in parseColumnOrder(SettingsStore.instance.columnOrder.value))
    if (columnAvailable(col)) col,
];

String columnWidthKey(FileColumn col) => col.name;

Map<String, double> parseColumnWidths(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) return const {};

    return {
      for (final entry in decoded.entries)
        if (entry.value is num) entry.key: (entry.value as num).toDouble(),
    };
  } catch (_) {
    return const {};
  }
}

String columnWidthsToString(Map<String, double> widths) {
  final sorted = Map<String, double>.fromEntries(
    widths.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );

  return jsonEncode(sorted);
}

double minColumnWidth(String key) {
  if (key == _kColumnWidthsNameKey) return _kNameMinWidth;
  if (key == _kColumnWidthsLocationKey) return _kLocationMinWidth;

  return 56;
}

String _formatDateBy(
  DateTime d,
  String mode, {
  required bool recentDatesRelative,
}) => formatEntryDate(d, mode, recentDatesRelative: recentDatesRelative);
