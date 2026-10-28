import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'compare_controller.dart';
import 'compare_excludes.dart';

class CompareExcludesField extends StatefulWidget {
  final CompareController controller;

  const CompareExcludesField({super.key, required this.controller});

  @override
  State<CompareExcludesField> createState() => _CompareExcludesFieldState();
}

class _CompareExcludesFieldState extends State<CompareExcludesField> {
  late final TextEditingController _text;
  late final FocusNode _fieldFocus;
  final _wrapperFocus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.controller.effectiveExcludePatterns.value,
    );
    _fieldFocus = FocusNode();
  }

  @override
  void dispose() {
    _text.dispose();
    _fieldFocus.dispose();
    _wrapperFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _fieldFocus.hasPrimaryFocus) {
      _text.text = widget.controller.effectiveExcludePatterns.value;

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _save(String value) async {
    if (_busy) return;
    if (value == widget.controller.effectiveExcludePatterns.value) return;
    setState(() => _busy = true);
    final ok = await widget.controller.saveExcludePatterns(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      showToast(context: context, message: t.compare.excludeSaveFailed);
    }
  }

  void _apply() => _save(_text.text.trim());

  void _clear() {
    if (_busy) return;
    _text.clear();
    _save('');
  }

  @override
  Widget build(BuildContext context) {
    final hasPatterns = !CompareExcludes.parse(
      widget.controller.effectiveExcludePatterns.value,
    ).isEmpty;

    return Focus(
      focusNode: _wrapperFocus,
      canRequestFocus: false,
      onKeyEvent: _onKeyEvent,
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          border: Border.all(color: AppColors.bgDivider),
        ),
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          children: [
            Tooltip(
              message: t.compare.excludeSavedHint,
              child: Icon(
                WaydirIconsRegular.prohibit,
                size: 11,
                color: AppColors.fgMuted,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _fieldFocus,
                onSubmitted: (_) => _apply(),
                style: context.txt.captionSmall,
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: InputBorder.none,
                  hintText: t.compare.excludePlaceholder,
                  hintStyle: context.txt.captionSmall.copyWith(
                    color: AppColors.fgSubtle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _ClearButton(enabled: hasPatterns && !_busy, onTap: _clear),
          ],
        ),
      ),
    );
  }
}

class _ClearButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _ClearButton({required this.enabled, required this.onTap});

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: t.compare.excludeClear,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered && widget.enabled
                  ? AppColors.bgHover
                  : Colors.transparent,
            ),
            child: Icon(
              WaydirIconsRegular.x,
              size: 12,
              color: widget.enabled
                  ? (_hovered ? AppColors.fg : AppColors.fgMuted)
                  : AppColors.fgSubtle,
            ),
          ),
        ),
      ),
    );
  }
}
