import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../i18n/strings.g.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/app_theme.dart';

class QuickLookShortcutBar extends StatelessWidget {
  final Signal<bool> editorActive;
  final List<QuickLookShortcutHint> Function(bool editing) hints;

  const QuickLookShortcutBar({
    super.key,
    required this.editorActive,
    required this.hints,
  });

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final items = hints(editorActive.value);

        return Container(
          height: 30,
          color: AppColors.bgStatus,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  items[i],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class QuickLookShortcutHint extends StatelessWidget {
  final List<String> caps;
  final String label;

  const QuickLookShortcutHint({
    super.key,
    required this.caps,
    required this.label,
  });

  static String get ctrlCap => Platform.isMacOS ? '⌘' : 'Ctrl';

  static List<String> capsOf(String id) =>
      AppShortcuts.getById(id).displayKeys.split('+');

  static List<QuickLookShortcutHint> editing() => [
    QuickLookShortcutHint(caps: const ['F6'], label: t.quickLook.hintView),
    QuickLookShortcutHint(
      caps: capsOf('quick_look_save'),
      label: t.quickLook.save,
    ),
    QuickLookShortcutHint(caps: const ['F5'], label: t.quickLook.hintReload),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < caps.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Text(
            caps[i],
            style: context.txt.keyCap.copyWith(color: AppColors.fg),
          ),
        ],
        const SizedBox(width: 5),
        Text(
          label,
          style: context.txt.caption.copyWith(color: AppColors.fgMuted),
        ),
      ],
    );
  }
}
