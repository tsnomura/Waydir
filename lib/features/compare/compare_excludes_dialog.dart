import 'package:flutter/material.dart';

import '../../core/settings/settings_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_text_field.dart';
import 'compare_controller.dart';

Future<void> showCompareExcludesDialog(
  BuildContext context,
  CompareController controller,
) async {
  final store = SettingsStore.instance;
  final text = TextEditingController(text: store.compareExcludePatterns.value);
  final save = t.compare.excludeSave;
  final result = await showCustomDialog<String>(
    context: context,
    title: t.compare.excludeTitle,
    icon: WaydirIconsRegular.prohibit,
    width: 460,
    body: _ExcludesBody(text: text),
    actions: [
      DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
      DialogAction(label: save, color: AppColors.accent),
    ],
  );
  final raw = result == save
      ? text.text.trim()
      : store.compareExcludePatterns.value;
  text.dispose();
  if (raw == store.compareExcludePatterns.value) return;
  store.compareExcludePatterns.value = raw;
  if (controller.active.value) await controller.start();
}

class _ExcludesBody extends StatelessWidget {
  final TextEditingController text;

  const _ExcludesBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: text,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          style: context.txt.body,
          cursorColor: AppColors.accent,
          decoration: appInputDecoration(
            hintText: t.compare.excludePlaceholder,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t.preferences.general.compareExcludePatternsHint,
          style: context.txt.muted,
        ),
      ],
    );
  }
}
