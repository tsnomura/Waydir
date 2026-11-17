part of '../file_view.dart';

class _LocationText extends StatelessWidget {
  final String location;
  final bool showForCursor;

  const _LocationText(this.location, {this.showForCursor = false});

  @override
  Widget build(BuildContext context) {
    final style = context.txt.muted;
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shown = ellipsizePathStart(
          location,
          textFits(
            style: style,
            scaler: scaler,
            maxWidth: constraints.maxWidth,
          ),
          separator: p.separator,
        );
        final text = Text(
          shown,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.right,
          style: style,
        );
        if (shown == location) return text;

        return CursorTooltip(
          message: location,
          showForCursor: showForCursor,
          child: text,
        );
      },
    );
  }
}

class _ListRow extends FileItemWidget {
  final bool cursorTooltips;
  final bool isCut;
  final bool isFolderDragOver;
  final FileMenuActionCallback? onMenuAction;
  final bool recursive;
  final double nameWidth;
  final double locationWidth;
  final List<FileColumn> columns;
  final Map<FileColumn, double> columnWidths;
  final double rowHeight;
  final double iconSize;
  final String dateFmt;
  final bool recentDatesRelative;
  final String? location;
  final int? folderSize;
  final double sizeFraction;
  final RowDecoration? rowDecoration;
  final bool showStatus;
  final bool treeMode;
  final int treeDepth;
  final bool treeExpanded;
  final bool treeLoading;
  final VoidCallback? onToggleTree;

  const _ListRow({
    required super.entry,
    required super.index,
    this.folderSize,
    this.sizeFraction = 0,
    this.rowDecoration,
    required super.selection,
    this.cursorTooltips = false,
    this.isCut = false,
    this.isFolderDragOver = false,
    super.isRenaming = false,
    super.renameAttempt = 0,
    super.onRenameSubmit,
    super.onRenameCancel,
    required super.onSelect,
    required super.onOpen,
    super.onContextMenu,
    this.onMenuAction,
    this.recursive = false,
    this.nameWidth = 0,
    this.locationWidth = _kLocationWidth,
    this.columns = const [],
    this.columnWidths = const {},
    this.rowHeight = _kRowHeightComfortable,
    this.iconSize = 16,
    this.dateFmt = 'locale',
    this.recentDatesRelative = true,
    this.location,
    super.onOpenInNewTab,
    super.onOpenInOtherPaneNewTab,
    this.showStatus = false,
    this.treeMode = false,
    this.treeDepth = 0,
    this.treeExpanded = false,
    this.treeLoading = false,
    this.onToggleTree,
  });

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> with FileItemState<_ListRow> {
  bool _hovered = false;
  bool _treeDisclosureHovered = false;

  Color get _bg {
    if (widget.isFolderDragOver) {
      return AppColors.accent.withValues(alpha: 0.12);
    }
    if (dragging) return AppColors.accent.withValues(alpha: 0.08);
    if (marked.value) return AppColors.bgSelectedMuted;
    if (cursorOn.value) return AppColors.bgHoverStrong;
    if (_hovered && !PointerHoverStore.instance.suppressed.value) {
      return AppColors.bgHover;
    }
    final decoration = widget.rowDecoration;
    if (decoration != null && decoration.badge == null) {
      return decoration.tint.withValues(alpha: 0.18);
    }

    return Colors.transparent;
  }

  double get _leftBorderWidth {
    if (marked.value) return 2;
    if (cursorOn.value) return 1;

    return 0;
  }

  double get _rightBorderWidth {
    if (cursorOn.value) return 1;

    return 0;
  }

  Gradient? get _sizeBar {
    final fraction = widget.sizeFraction.clamp(0.0, 1.0);
    if (fraction <= 0) return null;
    final bg = _bg;
    final bar = Color.alphaBlend(AppColors.accent.withValues(alpha: 0.22), bg);

    return LinearGradient(
      colors: [bar, bar, bg, bg],
      stops: [0, fraction, fraction, 1],
    );
  }

  BoxBorder? get _border {
    if (widget.isFolderDragOver) {
      return Border.all(color: AppColors.accent.withValues(alpha: 0.4));
    }
    if (cursorOn.value) {
      final outline = BorderSide(
        color: AppColors.accent.withValues(alpha: 0.7),
      );

      return Border(
        top: outline,
        right: outline,
        bottom: outline,
        left: marked.value
            ? BorderSide(color: AppColors.accent, width: 2)
            : outline,
      );
    }
    if (marked.value) {
      return Border(left: BorderSide(color: AppColors.accent, width: 2));
    }

    return null;
  }

  Widget _buildTagDots() {
    final colors = widget.rowDecoration?.badgeColors ?? const [];
    if (colors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final color in colors)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIconWithBadge(FileEntry e) {
    return FileEntryIcon(entry: e, size: widget.iconSize);
  }

  Widget _buildStatusCell() {
    if (!widget.showStatus) return const SizedBox.shrink();
    final decoration = widget.rowDecoration;
    final badge = decoration?.badge;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: badge == null
          ? SizedBox(width: widget.iconSize)
          : StatusChip(
              glyph: badge,
              color: decoration!.tint,
              size: widget.iconSize,
            ),
    );
  }

  Widget _buildTreePrefix(bool isFolder) {
    if (!widget.treeMode) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: widget.treeDepth * _kTreeIndentWidth),
        SizedBox(
          width: _kTreeDisclosureWidth,
          height: widget.rowHeight,
          child: isFolder
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _treeDisclosureHovered = true),
                  onExit: (_) => setState(() => _treeDisclosureHovered = false),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggleTree,
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _treeDisclosureHovered
                              ? AppColors.bgHoverStrong
                              : Colors.transparent,
                          border: Border.all(
                            color: _treeDisclosureHovered
                                ? AppColors.borderColor
                                : Colors.transparent,
                          ),
                        ),
                        child: widget.treeLoading
                            ? SizedBox(
                                width: 10,
                                height: 10,
                                child: AppSpinner(
                                  strokeWidth: 1.5,
                                  color: AppColors.fgSubtle,
                                ),
                              )
                            : Icon(
                                widget.treeExpanded
                                    ? WaydirIconsRegular.caretDown
                                    : WaydirIconsRegular.caretRight,
                                size: 12,
                                color: _treeDisclosureHovered
                                    ? AppColors.fg
                                    : AppColors.fgSubtle,
                              ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  List<Widget> _buildColumnCells(BuildContext context, FileEntry e) {
    final muted = context.txt.muted;

    return [
      for (final col in widget.columns) ...[
        const SizedBox(width: _kColumnGap),
        SizedBox(
          width: widget.columnWidths[col] ?? 0,
          child: Text(
            fileColumnText(
              col,
              e,
              dateFmt: widget.dateFmt,
              recentDatesRelative: widget.recentDatesRelative,
              folderSize: widget.folderSize,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: muted,
          ),
        ),
      ],
    ];
  }

  Widget _buildDragImage(BuildContext context, Widget child) {
    final dragCount = marked.value
        ? widget.selection.selectedPaths.peek().length
        : 1;

    final e = widget.entry;

    final visualRow = Container(
      width: 260,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSidebar,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.bgDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          FileEntryIcon(entry: e, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dragCount > 1 ? t.fileView.movingItems(count: dragCount) : e.name,
              overflow: TextOverflow.ellipsis,
              style: context.txt.dialogTitle.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return visualRow;
  }

  @override
  Widget build(BuildContext context) => SignalBuilder(builder: _build);

  Widget _build(BuildContext context) {
    final e = widget.entry;
    final isFolder = e.type == FileItemType.folder;
    final opacity = e.isGhost
        ? 0.5
        : widget.isCut
        ? 0.4
        : (dragging ? 0.4 : 1.0);

    if (widget.isRenaming) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          height: widget.rowHeight,
          padding: const EdgeInsets.only(
            left: _kRowPaddingLeft,
            right: _kRowPaddingRight,
          ),
          decoration: BoxDecoration(color: _bg, border: _border),
          child: Opacity(
            opacity: opacity,
            child: Row(
              children: [
                _buildStatusCell(),
                _buildTreePrefix(isFolder),
                _buildIconWithBadge(e),
                const SizedBox(width: 6),
                SizedBox(
                  width: widget.nameWidth,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          cancelRename,
                    },
                    child: TextField(
                      controller: renameController,
                      focusNode: renameFocusNode,
                      autofocus: true,
                      style: context.txt.bodyEmphasis,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        filled: true,
                        fillColor: AppColors.bgInput,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: AppColors.accent,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: AppColors.bgDivider,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: AppColors.accent,
                            width: 1,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => commitRename(),
                      onTapOutside: (_) => commitRename(),
                    ),
                  ),
                ),
                if (widget.recursive) ...[
                  const SizedBox(width: _kColumnGap),
                  SizedBox(
                    width: widget.locationWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _LocationText(
                        widget.location ?? '',
                        showForCursor: cursorOn.value && widget.cursorTooltips,
                      ),
                    ),
                  ),
                ],
                ..._buildColumnCells(context, e),
              ],
            ),
          ),
        ),
      );
    }

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: handleTap,
        onSecondaryTapUp: handleSecondaryTap,
        onTertiaryTapUp: (_) {
          if (widget.entry.type == FileItemType.folder) {
            widget.onOpenInNewTab?.call(widget.entry.path);
          }
        },
        child: Container(
          height: widget.rowHeight,
          padding: EdgeInsets.only(
            left: _kRowPaddingLeft - _leftBorderWidth,
            right: _kRowPaddingRight - _rightBorderWidth,
          ),
          decoration: BoxDecoration(
            color: _sizeBar == null ? _bg : null,
            gradient: _sizeBar,
            borderRadius: widget.isFolderDragOver ? BorderRadius.zero : null,
            border: _border,
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              children: [
                _buildStatusCell(),
                _buildTreePrefix(isFolder),
                _buildIconWithBadge(e),
                const SizedBox(width: 6),
                SizedBox(
                  width: widget.nameWidth,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          e.name,
                          overflow: TextOverflow.ellipsis,
                          style: e.isGhost
                              ? context.txt.body.copyWith(
                                  color: AppColors.fgSubtle,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: AppColors.fgSubtle,
                                )
                              : context.txt.body.copyWith(
                                  color: marked.value
                                      ? AppColors.fg
                                      : AppColors.fg.withValues(alpha: 0.9),
                                  fontWeight: marked.value
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                        ),
                      ),
                      _buildTagDots(),
                    ],
                  ),
                ),
                if (widget.recursive) ...[
                  const SizedBox(width: _kColumnGap),
                  SizedBox(
                    width: widget.locationWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _LocationText(
                        widget.location ?? '',
                        showForCursor: cursorOn.value && widget.cursorTooltips,
                      ),
                    ),
                  ),
                ],
                ..._buildColumnCells(context, e),
              ],
            ),
          ),
        ),
      ),
    );

    if (e.isGhost) return row;

    return DragItemWidget(
      dragItemProvider: provideDragItem,
      allowedOperations: () => [DropOperation.copy, DropOperation.move],
      canAddItemToExistingSession: true,
      dragBuilder: _buildDragImage,
      child: DraggableWidget(
        onDragConfiguration: expandDragConfiguration,
        child: row,
      ),
    );
  }
}
