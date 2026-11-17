import 'package:flutter/widgets.dart';
import 'package:signals/signals.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/models/file_entry.dart';
import '../../i18n/strings.g.dart';
import '../../ui/overlays/toast.dart';
import '../../utils/drag_drop.dart';
import '../operations/drag_hint.dart';
import 'file_list_selection.dart';
import 'file_view.dart' show FileDropCallback;

/// What the list and the grid do the same way: follow the cursor with the
/// scroll position, and accept files dropped onto the view or onto a folder.
mixin FileViewBehavior<T extends StatefulWidget> on State<T> {
  FileListSelection get viewSelection;

  void revealCursor();

  void reportCursorRow();

  bool isDragOver = false;
  String? hoveredFolderPath;
  void Function()? _cursorDisposer;

  void watchCursor() {
    _cursorDisposer?.call();
    var first = true;
    _cursorDisposer = effect(() {
      viewSelection.cursorIndex.value;
      if (first) {
        first = false;

        return;
      }
      untracked(_onCursorMoved);
    });
  }

  void stopWatchingCursor() {
    _cursorDisposer?.call();
    _cursorDisposer = null;
  }

  void _onCursorMoved() {
    if (!mounted) return;
    revealCursor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reportCursorRow();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String? _dropFolder(FileEntry? entry) {
    if (entry == null || entry.isGhost) return null;

    return entry.type == FileItemType.folder ? entry.path : null;
  }

  void _updateDropHover(FileEntry? entry) {
    final folder = _dropFolder(entry);
    if (folder == hoveredFolderPath && isDragOver) return;
    setState(() {
      isDragOver = true;
      hoveredFolderPath = folder;
    });
  }

  void _clearDropHover() {
    if (!isDragOver && hoveredFolderPath == null) return;
    setState(() {
      isDragOver = false;
      hoveredFolderPath = null;
    });
  }

  Widget buildDropRegion({
    required FileEntry? Function(Offset localPosition) entryAt,
    required String Function() currentPath,
    required FileDropCallback? Function() onDropFiles,
    required Widget child,
  }) {
    return DropRegion(
      formats: [Formats.fileUri, formatLocalFile],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        _updateDropHover(entryAt(event.position.local));
        if (isVirtualDrop(event.session)) return DropOperation.copy;

        return DragHintController.instance.mode.value == DragMode.move
            ? DropOperation.move
            : DropOperation.copy;
      },
      onDropLeave: (_) => _clearDropHover(),
      onDropEnded: (_) => _clearDropHover(),
      onPerformDrop: (event) async {
        final target = _dropFolder(entryAt(event.position.local));
        final virtual = isVirtualDrop(event.session);
        final paths = await pathsFromSession(
          event.session,
          onReceiving: (count) => showToast(
            context: context,
            message: t.toast.receivingDroppedItems(count: count),
          ),
        );
        final move =
            !virtual && DragHintController.instance.mode.value == DragMode.move;
        if (paths.isNotEmpty) {
          onDropFiles()?.call(paths, target ?? currentPath(), move: move);
        }
        _clearDropHover();
      },
      child: child,
    );
  }
}
