import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/models/file_entry.dart';
import '../../features/files/file_icons.dart';
import '../../i18n/strings.g.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'code_editor.dart';
import 'diff/diff_preview.dart';
import 'diff/diff_runner.dart';
import 'generators/generator_page_controller.dart';
import 'generators/generator_preview.dart';
import 'generators/generator_registry.dart';
import 'image_preview.dart';
import 'info_panel.dart';
import 'markdown_preview.dart';
import 'pdf_preview.dart';
import 'quick_look_common.dart';
import 'quick_look_io.dart';
import 'quick_look_zoom.dart';

bool defaultCompactFor(FileEntry? entry) {
  if (entry == null || entry.type == FileItemType.folder) return true;
  final ext = entry.extension;

  return !imageExts.contains(ext) &&
      !pdfExts.contains(ext) &&
      !markdownExts.contains(ext);
}

class QuickLookHeader extends StatelessWidget {
  final FileEntry? entry;
  final String? nameSuffix;
  final VoidCallback? onOpen;
  final bool compact;
  final bool showInfo;
  final VoidCallback onToggleInfo;
  final VoidCallback onClose;
  final int? multiCount;
  final CodeEditorController editorController;
  final bool markdownRendered;
  final VoidCallback? onToggleMarkdownView;
  final VoidCallback? onReload;
  final GestureDragStartCallback? onHeaderPanStart;
  final GestureDragUpdateCallback? onHeaderPanUpdate;
  final VoidCallback? onToggleMaximize;

  const QuickLookHeader({
    super.key,
    required this.entry,
    required this.compact,
    required this.showInfo,
    required this.onToggleInfo,
    required this.onClose,
    required this.editorController,
    this.nameSuffix,
    this.onOpen,
    this.multiCount,
    this.markdownRendered = true,
    this.onToggleMarkdownView,
    this.onReload,
    this.onHeaderPanStart,
    this.onHeaderPanUpdate,
    this.onToggleMaximize,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final multi = multiCount != null;
    final baseName = multi
        ? t.quickLook.items(count: multiCount!)
        : e?.name ?? t.quickLook.noSelection;
    final suffix = nameSuffix;
    final name = suffix == null ? baseName : '$baseName $suffix';
    final hasPreview = !multi && e != null && !compact;
    final isMarkdown =
        !multi &&
        e != null &&
        markdownExts.contains(e.extension) &&
        onToggleMarkdownView != null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onHeaderPanStart,
      onPanUpdate: onHeaderPanUpdate,
      child: Container(
        height: 46,
        color: AppColors.bgSidebar,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (multi)
              Icon(WaydirIconsRegular.copy, size: 18, color: AppColors.accent)
            else if (e == null)
              Icon(WaydirIconsRegular.file, size: 18, color: AppColors.fgMuted)
            else
              buildFileIcon(
                name: e.name,
                ext: e.extension,
                isFolder: e.type == FileItemType.folder,
                size: 18,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: context.txt.bodyEmphasis,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (isMarkdown) ...[
              SignalBuilder(
                builder: (context) {
                  final blocked =
                      !markdownRendered && editorController.dirty.value;

                  return QuickLookHeaderButton(
                    icon: markdownRendered
                        ? WaydirIconsRegular.code
                        : WaydirIconsRegular.eye,
                    active: false,
                    enabled: !blocked,
                    tooltip: blocked
                        ? t.quickLook.saveBeforePreview
                        : markdownRendered
                        ? t.quickLook.viewSource
                        : t.quickLook.viewRendered,
                    onTap: onToggleMarkdownView!,
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
            if (onOpen != null && !multi && e != null) ...[
              QuickLookHeaderButton(
                icon: WaydirIconsRegular.arrowSquareOut,
                active: false,
                tooltip: t.quickLook.openInApp,
                onTap: onOpen!,
              ),
              const SizedBox(width: 4),
            ],
            if (!multi && e != null && onReload != null) ...[
              QuickLookHeaderButton(
                icon: WaydirIconsRegular.arrowClockwise,
                active: false,
                tooltip: t.quickLook.reload,
                onTap: onReload!,
              ),
              const SizedBox(width: 4),
            ],
            if (hasPreview) ...[
              QuickLookHeaderButton(
                icon: WaydirIconsRegular.info,
                active: showInfo,
                tooltip: t.menu.properties,
                onTap: onToggleInfo,
              ),
              const SizedBox(width: 4),
            ],
            if (onToggleMaximize != null) ...[
              QuickLookMaximizeButton(onTap: onToggleMaximize!),
              const SizedBox(width: 4),
            ],
            QuickLookCloseButton(onTap: onClose),
          ],
        ),
      ),
    );
  }
}

class QuickLookHeaderButton extends StatefulWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  const QuickLookHeaderButton({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<QuickLookHeaderButton> createState() => QuickLookHeaderButtonState();
}

class QuickLookHeaderButtonState extends State<QuickLookHeaderButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final hovered = widget.enabled && _hover;
    final bg = active
        ? AppColors.accent.withValues(alpha: 0.16)
        : hovered
        ? AppColors.bgHover
        : Colors.transparent;
    final fg = !widget.enabled
        ? AppColors.fgSubtle
        : active
        ? AppColors.accent
        : hovered
        ? AppColors.fg
        : AppColors.fgMuted;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}

class QuickLookMaximizeButton extends StatefulWidget {
  final VoidCallback onTap;

  const QuickLookMaximizeButton({super.key, required this.onTap});

  @override
  State<QuickLookMaximizeButton> createState() =>
      _QuickLookMaximizeButtonState();
}

class _QuickLookMaximizeButtonState extends State<QuickLookMaximizeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = _hover ? AppColors.fg : AppColors.fgMuted;

    return Tooltip(
      message: t.quickLook.maximizeRestore,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            color: _hover ? AppColors.bgHover : Colors.transparent,
            child: Center(
              child: CustomPaint(
                size: const Size(10, 10),
                painter: _MaximizeGlyphPainter(fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MaximizeGlyphPainter extends CustomPainter {
  final Color color;

  const _MaximizeGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width - 1, size.height - 1), p);
  }

  @override
  bool shouldRepaint(covariant _MaximizeGlyphPainter old) => old.color != color;
}

class QuickLookCloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const QuickLookCloseButton({super.key, required this.onTap});

  @override
  State<QuickLookCloseButton> createState() => QuickLookCloseButtonState();
}

class QuickLookCloseButtonState extends State<QuickLookCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover ? AppColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Icon(
            Icons.close,
            size: 16,
            color: _hover ? AppColors.fg : AppColors.fgMuted,
          ),
        ),
      ),
    );
  }
}

Widget splitPreview(
  Widget preview,
  FileEntry entry, {
  required bool showInfo,
  ScrollController? scrollController,
}) {
  final scrollablePreview = scrollController == null
      ? preview
      : PrimaryScrollController(
          controller: scrollController,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: preview,
        );
  if (!showInfo) return scrollablePreview;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: scrollablePreview),
      Container(width: 1, color: AppColors.bgDivider),
      SizedBox(
        width: panelWidth,
        child: PrimaryScrollController.none(child: InfoPanel(entry: entry)),
      ),
    ],
  );
}

class QuickLookBody extends StatelessWidget {
  final FileEntry? entry;
  final Signal<bool> editorActive;
  final CodeEditorController editorController;
  final bool showInfo;
  final ValueChanged<bool> onCompactChanged;
  final bool markdownRendered;
  final ScrollController scrollController;
  final GeneratorPageController generatorPage;

  const QuickLookBody({
    super.key,
    required this.entry,
    required this.editorActive,
    required this.editorController,
    required this.showInfo,
    required this.onCompactChanged,
    required this.markdownRendered,
    required this.scrollController,
    required this.generatorPage,
  });

  @override
  Widget build(BuildContext context) =>
      QuickLookZoomArea(child: Builder(builder: _buildContent));

  Widget _buildContent(BuildContext context) {
    final e = entry;
    void release() => WidgetsBinding.instance.addPostFrameCallback(
      (_) => editorActive.value = false,
    );

    if (e == null || e.type == FileItemType.folder) {
      release();
      onCompactChanged(true);

      return PropertiesOnly(entry: e);
    }
    // Checked first, ahead of every built-in preview: a configured generator
    // is an explicit, deliberate choice to handle this extension a specific
    // way, so it wins even over a built-in that would otherwise apply (e.g.
    // pdf).
    final generator = GeneratorRegistry.instance.forExtension(e.extension);
    if (generator != null) {
      release();
      onCompactChanged(false);

      return splitPreview(
        GeneratorPreview(
          entry: e,
          page: generatorPage,
          editorActive: editorActive,
          scrollController: scrollController,
        ),
        e,
        showInfo: showInfo,
      );
    }
    if (imageExts.contains(e.extension)) {
      release();
      onCompactChanged(false);

      return splitPreview(
        ImagePreview(path: e.realPath),
        e,
        showInfo: showInfo,
      );
    }
    if (pdfExts.contains(e.extension)) {
      release();
      onCompactChanged(false);

      return splitPreview(
        PdfPreview(path: e.realPath),
        e,
        showInfo: showInfo,
        scrollController: scrollController,
      );
    }
    if (markdownExts.contains(e.extension) && markdownRendered) {
      release();
      onCompactChanged(false);

      return splitPreview(
        MarkdownPreview(entry: e),
        e,
        showInfo: showInfo,
        scrollController: scrollController,
      );
    }
    if (binaryExts.contains(e.extension)) {
      release();
      onCompactChanged(true);

      return PropertiesOnly(entry: e);
    }

    return QuickLookProbeLoader(
      entry: e,
      editorActive: editorActive,
      editorController: editorController,
      showInfo: showInfo,
      onCompactChanged: onCompactChanged,
      scrollController: scrollController,
    );
  }
}

/// Attempts a side-by-side diff of [left] and [right] (the two files
/// selected across panes in compare mode) and falls back to [fallback] —
/// Quick Look's normal single-file preview — whenever the configured diff
/// command is missing, errors, times out, or isn't set up at all.
class QuickLookDiffAttempt extends StatelessWidget {
  final FileEntry left;
  final FileEntry right;
  final Signal<bool> editorActive;
  final ValueChanged<bool> onCompactChanged;
  final VoidCallback onIdentical;
  final WidgetBuilder fallback;

  const QuickLookDiffAttempt({
    super.key,
    required this.left,
    required this.right,
    required this.editorActive,
    required this.onCompactChanged,
    required this.onIdentical,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return AsyncRetain<TextDiffResult>(
      cacheKey: DiffRunner.cacheKeyFor(left, right),
      loader: () => DiffRunner.run(left, right),
      loading: const QlCentered.spinner(),
      builder: (result) {
        if (result.identical) {
          onIdentical();

          return fallback(context);
        }
        if (!result.available) return fallback(context);
        onCompactChanged(false);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => editorActive.value = false,
        );

        return TextDiffView(left: left, right: right, result: result);
      },
    );
  }
}

class QuickLookProbeLoader extends StatelessWidget {
  final FileEntry entry;
  final Signal<bool> editorActive;
  final CodeEditorController editorController;
  final bool showInfo;
  final ValueChanged<bool> onCompactChanged;
  final ScrollController scrollController;

  const QuickLookProbeLoader({
    super.key,
    required this.entry,
    required this.editorActive,
    required this.editorController,
    required this.showInfo,
    required this.onCompactChanged,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    void release() => WidgetsBinding.instance.addPostFrameCallback(
      (_) => editorActive.value = false,
    );

    return AsyncRetain<Probe>(
      cacheKey: entry.realPath,
      loader: () => probeFile(entry),
      loading: const QlCentered.spinner(),
      builder: (res) {
        switch (res.kind) {
          case QlKind.text:
            onCompactChanged(false);

            return splitPreview(
              CodeEditor(
                key: ValueKey(entry.realPath),
                path: entry.realPath,
                extension: entry.extension,
                initial: res.text,
                format: res.format,
                editorActive: editorActive,
                controller: editorController,
                verticalScrollController: scrollController,
              ),
              entry,
              showInfo: showInfo,
            );
          case QlKind.binary:
          case QlKind.tooLarge:
            release();
            onCompactChanged(true);

            return PropertiesOnly(entry: entry);
          case QlKind.error:
            release();
            onCompactChanged(true);

            return PropertiesOnly(entry: entry);
        }
      },
    );
  }
}
