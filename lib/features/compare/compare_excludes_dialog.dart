import 'package:flutter/material.dart';

import '../../core/settings/settings_store.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/app_text_field.dart';
import 'compare_controller.dart';

Future<void> showCompareExcludesDialog(
  BuildContext context,
  CompareController controller,
) async {
  final active = controller.active.value;
  final initial = active
      ? controller.effectiveExcludePatterns.value
      : SettingsStore.instance.compareExcludePatterns.value;
  final text = TextEditingController(text: initial);
  final save = t.compare.excludeSave;
  final result = await showCustomDialog<String>(
    context: context,
    title: t.compare.excludeTitle,
    icon: WaydirIconsRegular.prohibit,
    width: 460,
    body: _ExcludesBody(text: text, perDirectory: active),
    actions: [
      DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
      DialogAction(label: save, color: AppColors.accent),
    ],
  );
  final raw = result == save ? text.text.trim() : initial;
  text.dispose();
  if (result != save || raw == initial) return;
  final ok = await controller.saveExcludePatterns(raw);
  if (!ok && context.mounted) {
    showToast(context: context, message: t.compare.excludeSaveFailed);
  }
}

class _ExcludesBody extends StatelessWidget {
  final TextEditingController text;
  final bool perDirectory;

  const _ExcludesBody({required this.text, required this.perDirectory});

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
          perDirectory
              ? t.compare.excludeSavedHint
              : t.preferences.general.compareExcludePatternsHint,
          style: context.txt.muted,
        ),
      ],
    );
  }
}
