import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.g.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/overlays/toast.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_text_styles.dart';
import 'compare_controller.dart';
import 'compare_excludes.dart';

class CompareExcludesBar extends StatefulWidget {
  final CompareController controller;
  final VoidCallback onClose;

  const CompareExcludesBar({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<CompareExcludesBar> createState() => _CompareExcludesBarState();
}

class _CompareExcludesBarState extends State<CompareExcludesBar> {
  late final TextEditingController _text;
  late final FocusNode _fieldFocus;
  final _barFocus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.controller.effectiveExcludePatterns.value,
    );
    _fieldFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _fieldFocus.dispose();
    _barFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();

      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _save(String value) async {
    if (_busy) return;
    if (value == widget.controller.effectiveExcludePatterns.value) {
      widget.onClose();

      return;
    }
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
      focusNode: _barFocus,
      canRequestFocus: false,
      onKeyEvent: _onKeyEvent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.bgDivider)),
        ),
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              Tooltip(
                message: t.compare.excludeSavedHint,
                child: Icon(
                  WaydirIconsRegular.prohibit,
                  size: 14,
                  color: AppColors.fgMuted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _text,
                  focusNode: _fieldFocus,
                  onEditingComplete: () {},
                  onSubmitted: (_) => _apply(),
                  style: context.txt.body,
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 5),
                    border: InputBorder.none,
                    hintText: t.compare.excludePlaceholder,
                    hintStyle: context.txt.body.copyWith(
                      color: AppColors.fgSubtle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _BarButton(
                label: t.compare.excludeClear,
                enabled: hasPatterns && !_busy,
                onTap: _clear,
              ),
              const SizedBox(width: 6),
              _BarButton(
                label: t.compare.excludeApply,
                enabled: !_busy,
                onTap: _apply,
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: t.compare.excludeClose,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.bgDivider),
                      ),
                      child: Icon(
                        WaydirIconsRegular.x,
                        size: 14,
                        color: AppColors.fgMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _BarButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (_hovered ? AppColors.fg : AppColors.fgMuted)
        : AppColors.fgSubtle;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? AppColors.bgHover
                : Colors.transparent,
            border: Border.all(color: AppColors.bgDivider),
          ),
          child: Text(
            widget.label,
            style: context.txt.captionSmall.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
