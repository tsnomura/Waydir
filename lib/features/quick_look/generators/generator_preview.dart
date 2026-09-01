import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../../core/models/file_entry.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/icons/waydir_icons.dart';
import '../quick_look_common.dart';
import 'generator_page_controller.dart';
import 'generator_registry.dart';
import 'generator_runner.dart';

class GeneratorPreview extends StatelessWidget {
  final FileEntry entry;
  final GeneratorPageController page;

  const GeneratorPreview({super.key, required this.entry, required this.page});

  @override
  Widget build(BuildContext context) {
    final def = GeneratorRegistry.instance.forExtension(entry.extension);
    final pageCount = def?.pageCount ?? 1;
    page.pageCount = pageCount;

    return SignalBuilder(
      builder: (context) {
        final position = page.position.value.clamp(0, pageCount - 1);

        return Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Stack(
            children: [
              Positioned.fill(
                child: AsyncRetain<String?>(
                  cacheKey:
                      '${entry.realPath}|${entry.modifiedMs}|${entry.size}|$position',
                  loader: () =>
                      GeneratorRunner.preview(entry, position: position),
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
              if (pageCount > 1)
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
                        onTap: page.prev,
                      ),
                      const SizedBox(width: 8),
                      QlHudChip(text: '${position + 1} / $pageCount'),
                      const SizedBox(width: 8),
                      _PageButton(
                        icon: WaydirIconsRegular.caretRight,
                        enabled: position < pageCount - 1,
                        onTap: page.next,
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
