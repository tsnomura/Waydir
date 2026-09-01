import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/file_entry.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/icons/waydir_icons.dart';
import '../quick_look_common.dart';
import 'generator_runner.dart';

class GeneratorPreview extends StatelessWidget {
  final FileEntry entry;

  const GeneratorPreview({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      alignment: Alignment.center,
      child: AsyncRetain<String?>(
        cacheKey: '${entry.realPath}|${entry.modifiedMs}|${entry.size}',
        loader: () => GeneratorRunner.preview(entry),
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
    );
  }
}
