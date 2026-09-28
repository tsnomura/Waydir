import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../../core/models/file_entry.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/icons/waydir_icons.dart';
import '../quick_look_common.dart';
import 'generator_page_controller.dart';
import 'generator_runner.dart';

class GeneratorPreview extends StatelessWidget {
  final FileEntry entry;
  final GeneratorPageController page;

  const GeneratorPreview({super.key, required this.entry, required this.page});

  @override
  Widget build(BuildContext context) {
    return AsyncRetain<int>(
      cacheKey: '${entry.realPath}|${entry.modifiedMs}|${entry.size}',
      loader: () => GeneratorRunner.resolvePageCount(entry),
      loading: const QlCentered.spinner(),
      builder: (pageCount) =>
          _GeneratorPreviewBody(entry: entry, page: page, pageCount: pageCount),
    );
  }
}

class _GeneratorPreviewBody extends StatefulWidget {
  final FileEntry entry;
  final GeneratorPageController page;
  final int pageCount;

  const _GeneratorPreviewBody({
    required this.entry,
    required this.page,
    required this.pageCount,
  });

  @override
  State<_GeneratorPreviewBody> createState() => _GeneratorPreviewBodyState();
}

class _GeneratorPreviewBodyState extends State<_GeneratorPreviewBody> {
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _prefetchRemainingPages();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Runs every page's generator ahead of time in the background, so paging
  // through an mp4/pdf-style preview doesn't wait on ffmpeg/mutool per page.
  // Sequential rather than concurrent to avoid bursting helper processes at
  // once; GeneratorRunner.preview's in-flight memoization and on-disk cache
  // mean this never duplicates whatever page is already being fetched
  // on-demand for the currently displayed position.
  Future<void> _prefetchRemainingPages() async {
    if (widget.pageCount <= 1) return;
    for (var i = 0; i < widget.pageCount; i++) {
      if (_disposed) return;
      await GeneratorRunner.preview(widget.entry, position: i);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.page.pageCount = widget.pageCount;

    return SignalBuilder(
      builder: (context) {
        final position = widget.page.position.value.clamp(
          0,
          widget.pageCount - 1,
        );

        return Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Stack(
            children: [
              Positioned.fill(
                child: AsyncRetain<String?>(
                  cacheKey:
                      '${widget.entry.realPath}|${widget.entry.modifiedMs}|'
                      '${widget.entry.size}|$position',
                  loader: () =>
                      GeneratorRunner.preview(widget.entry, position: position),
                  loading: const QlCentered.spinner(),
                  builder: (path) {
                    if (path == null) {
                      return QlCentered(
                        icon: WaydirIconsRegular.file,
                        message: t.quickLook.noPreview,
                      );
                    }

                    return Image.file(File(path), fit: BoxFit.contain);
                  },
                ),
              ),
              if (widget.pageCount > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PageButton(
                        icon: WaydirIconsRegular.caretLeft,
                        enabled: position > 0,
                        onTap: widget.page.prev,
                      ),
                      const SizedBox(width: 8),
                      QlHudChip(text: '${position + 1} / ${widget.pageCount}'),
                      const SizedBox(width: 8),
                      _PageButton(
                        icon: WaydirIconsRegular.caretRight,
                        enabled: position < widget.pageCount - 1,
                        onTap: widget.page.next,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.bgSurface.withValues(alpha: 0.9),
            border: Border.all(color: AppColors.borderColor),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 14,
            color: enabled ? AppColors.fg : AppColors.fgSubtle,
          ),
        ),
      ),
    );
  }
}
