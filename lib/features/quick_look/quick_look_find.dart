import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'code_editor.dart';
import 'quick_look_content.dart';

class QuickLookFindPopup extends StatefulWidget {
  final CodeEditorController controller;

  const QuickLookFindPopup({super.key, required this.controller});

  @override
  State<QuickLookFindPopup> createState() => _QuickLookFindPopupState();
}

class _QuickLookFindPopupState extends State<QuickLookFindPopup> {
  final _escFocus = FocusNode();

  @override
  void dispose() {
    _escFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.find?.close();

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _close() => widget.controller.find?.close();

  @override
  Widget build(BuildContext context) {
    final find = widget.controller.find;
    if (find == null) return const SizedBox.shrink();

    return ValueListenableBuilder(
      valueListenable: find,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        final result = value.result;
        final counter = result == null
            ? (value.searching || value.option.pattern.isEmpty
                  ? ''
                  : t.quickLook.searchNoMatches)
            : '${result.index + 1}/${result.matches.length}';

        return Focus(
          focusNode: _escFocus,
          canRequestFocus: false,
          onKeyEvent: _onKeyEvent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.bgToolbar,
              border: Border.all(color: AppColors.borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  WaydirIconsRegular.magnifyingGlass,
                  size: 14,
                  color: AppColors.fgMuted,
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: find.findInputController,
                    focusNode: find.findInputFocusNode,
                    onEditingComplete: () =>
                        find.findInputFocusNode.requestFocus(),
                    onSubmitted: (_) => find.nextMatch(),
                    style: context.txt.body,
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      border: InputBorder.none,
                      hintText: t.quickLook.search,
                      hintStyle: context.txt.body.copyWith(
                        color: AppColors.fgSubtle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _FindToggle(
                  label: 'Aa',
                  active: value.option.caseSensitive,
                  tooltip: t.quickLook.searchCase,
                  onTap: find.toggleCaseSensitive,
                ),
                const SizedBox(width: 2),
                _FindToggle(
                  label: '.*',
                  active: value.option.regex,
                  tooltip: t.quickLook.searchRegex,
                  onTap: find.toggleRegex,
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 54,
                  child: Text(
                    counter,
                    textAlign: TextAlign.right,
                    style: context.txt.caption.copyWith(
                      color: result == null
                          ? AppColors.danger
                          : AppColors.fgMuted,
                    ),
                  ),
                ),
                QuickLookHeaderButton(
                  icon: WaydirIconsRegular.caretUp,
                  active: false,
                  enabled: result != null,
                  tooltip: t.quickLook.searchPrevious,
                  onTap: find.previousMatch,
                ),
                QuickLookHeaderButton(
                  icon: WaydirIconsRegular.caretDown,
                  active: false,
                  enabled: result != null,
                  tooltip: t.quickLook.searchNext,
                  onTap: find.nextMatch,
                ),
                QuickLookHeaderButton(
                  icon: WaydirIconsRegular.x,
                  active: false,
                  tooltip: t.quickLook.searchClose,
                  onTap: _close,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FindToggle extends StatelessWidget {
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _FindToggle({
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            child: Text(
              label,
              style: context.txt.caption.copyWith(
                color: active ? AppColors.accent : AppColors.fgMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
