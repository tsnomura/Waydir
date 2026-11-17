import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../core/models/file_entry.dart';
import '../../utils/drag_drop.dart';
import '../operations/drag_hint.dart';
import 'file_list_selection.dart';
import 'file_view.dart'
    show
        FileContextMenuCallback,
        FileOpenCallback,
        FileSelectCallback,
        OpenInNewTabCallback,
        RenameCancelCallback,
        RenameSubmitCallback;

const _kDoubleTapMs = 300;

/// What a list row and a grid tile have in common: the entry they show and
/// the callbacks for selecting, opening, renaming and dragging it.
abstract class FileItemWidget extends StatefulWidget {
  final FileEntry entry;
  final int index;
  final FileListSelection selection;
  final bool isRenaming;
  final int renameAttempt;
  final RenameSubmitCallback? onRenameSubmit;
  final RenameCancelCallback? onRenameCancel;
  final FileSelectCallback onSelect;
  final FileOpenCallback onOpen;
  final FileContextMenuCallback? onContextMenu;
  final OpenInNewTabCallback? onOpenInNewTab;
  final OpenInNewTabCallback? onOpenInOtherPaneNewTab;

  const FileItemWidget({
    super.key,
    required this.entry,
    required this.index,
    required this.selection,
    this.isRenaming = false,
    this.renameAttempt = 0,
    this.onRenameSubmit,
    this.onRenameCancel,
    required this.onSelect,
    required this.onOpen,
    this.onContextMenu,
    this.onOpenInNewTab,
    this.onOpenInOtherPaneNewTab,
  });
}

/// The behaviour shared by list rows and grid tiles: cursor and mark
/// subscriptions, the inline rename field, click handling and drag items.
mixin FileItemState<T extends FileItemWidget> on State<T> {
  bool dragging = false;
  DateTime? _lastTap;
  TextEditingController? renameController;
  FocusNode? renameFocusNode;
  bool _renameCommitted = false;
  late ReadonlySignal<bool> cursorOn = widget.selection.cursorAt(widget.index);
  late ReadonlySignal<bool> marked = widget.selection.marked(widget.entry.path);

  @override
  void initState() {
    super.initState();
    if (widget.isRenaming) _initRenameFields();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged = !identical(oldWidget.selection, widget.selection);
    if (selectionChanged || oldWidget.index != widget.index) {
      cursorOn = widget.selection.cursorAt(widget.index);
    }
    if (selectionChanged || oldWidget.entry.path != widget.entry.path) {
      marked = widget.selection.marked(widget.entry.path);
    }
    if (widget.isRenaming && !oldWidget.isRenaming) {
      _initRenameFields();
    } else if (!widget.isRenaming && oldWidget.isRenaming) {
      _disposeRenameFields();
    } else if (widget.isRenaming &&
        widget.renameAttempt != oldWidget.renameAttempt) {
      _renameCommitted = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = renameController;
        final focusNode = renameFocusNode;
        if (!mounted || focusNode == null || controller == null) return;
        focusNode.requestFocus();
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _disposeRenameFields();
    super.dispose();
  }

  void _initRenameFields() {
    _renameCommitted = false;
    final name = widget.entry.name;
    final dotIndex = widget.entry.type == FileItemType.file
        ? name.lastIndexOf('.')
        : -1;
    renameController = TextEditingController(text: name)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: dotIndex > 0 ? dotIndex : name.length,
      );
    renameFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) renameFocusNode?.requestFocus();
    });
  }

  void _disposeRenameFields() {
    renameController?.dispose();
    renameController = null;
    renameFocusNode?.dispose();
    renameFocusNode = null;
  }

  void commitRename() {
    if (_renameCommitted) return;
    _renameCommitted = true;
    widget.onRenameSubmit?.call(renameController?.text ?? '');
  }

  void reopenRename() => _renameCommitted = false;

  void cancelRename() {
    if (_renameCommitted) return;
    _renameCommitted = true;
    widget.onRenameCancel?.call();
  }

  FileSelectionEvent get _selectionEvent =>
      FileSelectionEvent(entry: widget.entry, index: widget.index);

  void handleTap() {
    final now = DateTime.now();
    final last = _lastTap;
    if (last == null || now.difference(last).inMilliseconds >= _kDoubleTapMs) {
      _lastTap = now;
      widget.onSelect(_selectionEvent);

      return;
    }
    _lastTap = null;
    final keys = HardwareKeyboard.instance;
    final isFolder = widget.entry.type == FileItemType.folder;
    if (widget.entry.isGhost) {
      widget.onSelect(_selectionEvent);
    } else if (isFolder && keys.isShiftPressed) {
      widget.onOpenInOtherPaneNewTab?.call(widget.entry.path);
    } else if (isFolder && keys.isControlPressed) {
      widget.onOpenInNewTab?.call(widget.entry.path);
    } else {
      widget.onOpen(widget.entry);
    }
  }

  void handleSecondaryTap(TapUpDetails details) {
    if (widget.entry.isGhost) return;
    widget.onContextMenu?.call(_selectionEvent, details.globalPosition);
  }

  List<String> pathsToDrag() {
    final selectedPaths = widget.selection.selectedPaths.peek().toList();
    if (marked.value && selectedPaths.isNotEmpty) return selectedPaths;

    return [widget.entry.path];
  }

  DragItem _dragItemForPaths(List<String> paths) {
    final item = DragItem(
      localData: {'paths': paths},
      suggestedName: paths.length == 1 ? p.basename(paths.first) : null,
    );
    item.add(formatLocalFile(paths.join('\n')));
    for (final path in paths) {
      item.add(Formats.fileUri(Uri.file(path)));
    }

    return item;
  }

  Future<DragItem?> provideDragItem(DragItemRequest request) async {
    if (HardwareKeyboard.instance.isShiftPressed) return null;

    final item = _dragItemForPaths(pathsToDrag());
    final initialMode = initialDragMode();

    void updateDragging() {
      final isDragging = request.session.dragging.value;
      if (mounted) setState(() => dragging = isDragging);
      if (isDragging) DragHintController.instance.mode.value = initialMode;
    }

    request.session.dragging.addListener(updateDragging);
    updateDragging();

    return item;
  }

  Future<DragConfiguration> expandDragConfiguration(
    DragConfiguration configuration,
    DragSession session,
  ) async {
    final paths = pathsToDrag();
    if (paths.length <= 1 || configuration.items.isEmpty) {
      return configuration;
    }

    final preview = configuration.items.first;
    final extraImages = <TargetedWidgetSnapshot>[];
    for (var i = 1; i < paths.length; i++) {
      extraImages.add(await _transparentDragSnapshot(preview.image));
    }

    return DragConfiguration(
      items: [
        for (final (index, path) in paths.indexed)
          DragConfigurationItem(
            item: _dragItemForPaths([path]),
            image: index == 0 ? preview.image : extraImages[index - 1],
          ),
      ],
      allowedOperations: configuration.allowedOperations,
      options: configuration.options,
    );
  }

  Future<TargetedWidgetSnapshot> _transparentDragSnapshot(
    TargetedWidgetSnapshot preview,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(Colors.transparent, ui.BlendMode.clear);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();

    return TargetedWidgetSnapshot(
      WidgetSnapshot.image(image),
      Rect.fromLTWH(preview.rect.left, preview.rect.top, 1, 1),
    );
  }
}
