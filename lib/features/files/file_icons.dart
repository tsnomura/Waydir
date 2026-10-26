import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:waydir/core/archive/archive_writer.dart';
import 'package:waydir/core/fs/fs_worker_pool.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/platform/platform_paths.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';
import '../../ui/theme/app_theme.dart';
import 'material_icons_map.dart';

Widget buildFileIcon({
  required String name,
  required String ext,
  required bool isFolder,
  double size = 20,
}) {
  if (isFolder) {
    final folderName = materialFolderNames[name.toLowerCase()];
    if (folderName != null) {
      return SvgPicture.asset(
        'assets/icons/material/$folderName.svg',
        width: size,
        height: size,
      );
    }

    return Icon(
      WaydirIconsFill.folder,
      size: size,
      color: AppColors.folderColor,
    );
  }

  final lowerName = name.toLowerCase();
  var iconName = materialFileNames[lowerName];
  iconName ??= materialFileExtensions[ext.toLowerCase()];
  iconName ??= 'document';

  return SvgPicture.asset(
    'assets/icons/material/$iconName.svg',
    width: size,
    height: size,
  );
}

class FileEntryIcon extends StatefulWidget {
  const FileEntryIcon({
    super.key,
    required this.entry,
    required this.size,
    this.isEncrypted,
  });

  final FileEntry entry;
  final double size;
  final FutureOr<bool> Function(String path)? isEncrypted;

  @override
  State<FileEntryIcon> createState() => _FileEntryIconState();
}

class _FileEntryIconState extends State<FileEntryIcon> {
  static final Map<String, bool> _encrypted = {};

  bool? _locked;

  static String _key(FileEntry e) => '${e.path}:${e.modifiedMs}';

  static bool _checkable(FileEntry e) =>
      e.type == FileItemType.file &&
      !e.isGhost &&
      !PlatformPaths.isRemoteUri(e.realPath) &&
      archiveFormatFromName(e.name) == ArchiveFormat.zip;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant FileEntryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.modifiedMs != widget.entry.modifiedMs) {
      _refresh();
    }
  }

  void _refresh() {
    final key = _key(widget.entry);
    final cached = _encrypted[key];
    if (cached != null) {
      _locked = cached;
      return;
    }
    if (!_checkable(widget.entry)) {
      _locked = false;
      return;
    }
    _runCheck();
  }

  Future<void> _runCheck() async {
    final key = _key(widget.entry);
    final check =
        widget.isEncrypted ?? FsWorkerPool.instance.archiveIsEncrypted;
    bool locked;
    try {
      locked = await check(widget.entry.realPath);
    } catch (_) {
      locked = false;
    }
    if (!mounted || key != _key(widget.entry)) return;
    _encrypted[key] = locked;
    setState(() => _locked = locked);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    if (_locked == true) {
      return SvgPicture.asset(
        'assets/icons/material/lock.svg',
        width: widget.size,
        height: widget.size,
      );
    }

    return buildFileIcon(
      name: e.name,
      ext: e.extension,
      isFolder: e.type == FileItemType.folder,
      size: widget.size,
    );
  }
}
