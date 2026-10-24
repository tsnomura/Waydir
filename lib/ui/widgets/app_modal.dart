import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import 'app_close_button.dart';

class AppModal extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final VoidCallback onClose;
  final Widget child;
  final List<Widget> titleBarActions;
  final GestureDragStartCallback? onTitleBarPanStart;
  final GestureDragUpdateCallback? onTitleBarPanUpdate;

  const AppModal({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    required this.onClose,
    required this.child,
    this.titleBarActions = const [],
    this.onTitleBarPanStart,
    this.onTitleBarPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final fixedHeight = height != null;
    final body = fixedHeight
        ? Expanded(child: _paddedChild)
        : Flexible(child: _paddedChild);

    return Align(
      alignment: Alignment.center,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: width,
          height: height,
          constraints: fixedHeight
              ? null
              : const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppColors.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Column(
              mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
              children: [
                _ModalTitleBar(
                  icon: icon,
                  iconColor: iconColor,
                  title: title,
                  onClose: onClose,
                  actions: titleBarActions,
                  onPanStart: onTitleBarPanStart,
                  onPanUpdate: onTitleBarPanUpdate,
                ),
                Container(height: 1, color: AppColors.bgDivider),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get _paddedChild {
    if (padding == EdgeInsets.zero) return child;

    return Padding(padding: padding, child: child);
  }
}

class _ModalTitleBar extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final VoidCallback onClose;
  final List<Widget> actions;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;

  const _ModalTitleBar({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onClose,
    this.actions = const [],
    this.onPanStart,
    this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: AppColors.bgSidebar),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor ?? AppColors.fgAccent),
              const SizedBox(width: 8),
            ],
            Text(title, style: context.txt.dialogTitle),
            const Spacer(),
            for (final action in actions) ...[action, const SizedBox(width: 4)],
            AppCloseButton(onTap: onClose),
          ],
        ),
      ),
    );
  }
}
