import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/file_entry.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/icons/waydir_icons.dart';
import '../quick_look_common.dart';
import 'generator_registry.dart';
import 'generator_runner.dart';

class GeneratorPreview extends StatefulWidget {
  final FileEntry entry;

  const GeneratorPreview({super.key, required this.entry});

  @override
  State<GeneratorPreview> createState() => _GeneratorPreviewState();
}

class _GeneratorPreviewState extends State<GeneratorPreview> {
  int _position = 0;

  @override
  void didUpdateWidget(GeneratorPreview old) {
    super.didUpdateWidget(old);
    if (old.entry.realPath != widget.entry.realPath) _position = 0;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final def = GeneratorRegistry.instance.forExtension(entry.extension);
    final pageCount = def?.pageCount ?? 1;
    final position = _position.clamp(0, pageCount - 1);

    return Container(
      color: AppColors.bg,
      alignment: Alignment.center,
      child: Stack(
        children: [
          Positioned.fill(
            child: AsyncRetain<String?>(
              cacheKey:
                  '${entry.realPath}|${entry.modifiedMs}|${entry.size}|$position',
              loader: () => GeneratorRunner.preview(entry, position: position),
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
                    onTap: () => setState(() => _position = position - 1),
                  ),
                  const SizedBox(width: 8),
                  QlHudChip(text: '${position + 1} / $pageCount'),
                  const SizedBox(width: 8),
                  _PageButton(
                    icon: WaydirIconsRegular.caretRight,
                    enabled: position < pageCount - 1,
                    onTap: () => setState(() => _position = position + 1),
                  ),
                ],
              ),
            ),
        ],
      ),
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
