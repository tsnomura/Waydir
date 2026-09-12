import 'package:flutter/material.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../core/terminal/bulk_copy_command.dart';
import '../../i18n/strings.g.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_modal.dart';
import 'dialog.dart';

class BulkCopyRequest {
  final String destinationDir;
  final List<String> flags;

  const BulkCopyRequest({required this.destinationDir, required this.flags});
}

Future<BulkCopyRequest?> showBulkCopyDialog({
  required BuildContext context,
  required BulkCopyTool tool,
  required String sourceName,
  required String defaultDestinationDir,
}) {
  return showDialog<BulkCopyRequest>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: _BulkCopyBody(
          tool: tool,
          sourceName: sourceName,
          defaultDestinationDir: defaultDestinationDir,
        ),
      ),
    ),
  );
}

class _BulkCopyBody extends StatefulWidget {
  final BulkCopyTool tool;
  final String sourceName;
  final String defaultDestinationDir;

  const _BulkCopyBody({
    required this.tool,
    required this.sourceName,
    required this.defaultDestinationDir,
  });

  @override
  State<_BulkCopyBody> createState() => _BulkCopyBodyState();
}

class _BulkCopyBodyState extends State<_BulkCopyBody> {
  late final TextEditingController _dest = TextEditingController(
    text: widget.defaultDestinationDir,
  )..addListener(_onDestChanged);
  late final Set<String> _enabledFlags = {
    for (final o in bulkCopyOptionsFor(widget.tool))
      if (o.defaultOn) o.flag,
  };

  bool get _valid => _dest.text.trim().isNotEmpty;

  void _onDestChanged() => setState(() {});

  @override
  void dispose() {
    _dest.removeListener(_onDestChanged);
    _dest.dispose();
    super.dispose();
  }

  void _toggle(String flag) {
    setState(() {
      if (!_enabledFlags.remove(flag)) _enabledFlags.add(flag);
    });
  }

  void _submit() {
    if (!_valid) return;
    final flags = [
      for (final o in bulkCopyOptionsFor(widget.tool))
        if (_enabledFlags.contains(o.flag)) o.flag,
    ];
    Navigator.of(
      context,
    ).pop(BulkCopyRequest(destinationDir: _dest.text.trim(), flags: flags));
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      icon: WaydirIconsRegular.terminal,
      title: t.bulkCopy.title(tool: bulkCopyToolName(widget.tool)),
      width: 460,
      padding: const EdgeInsets.all(20),
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.bulkCopy.source, style: context.txt.fieldLabel),
          const SizedBox(height: 6),
          Text(
            widget.sourceName,
            style: context.txt.body.copyWith(color: AppColors.fgMuted),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Text(t.bulkCopy.destination, style: context.txt.fieldLabel),
          const SizedBox(height: 6),
          AppTextField(
            controller: _dest,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          Text(t.bulkCopy.options, style: context.txt.fieldLabel),
          const SizedBox(height: 6),
          for (final option in bulkCopyOptionsFor(widget.tool))
            _FlagRow(
              label: '${option.label} (${option.flag})',
              value: _enabledFlags.contains(option.flag),
              onTap: () => _toggle(option.flag),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DialogButton(
                label: t.bulkCopy.cancel,
                color: AppColors.fgMuted,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              DialogButton(
                label: t.bulkCopy.insertCommand,
                color: _valid ? AppColors.accent : AppColors.fgSubtle,
                onTap: _valid ? _submit : () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  final String label;
  final bool value;
  final VoidCallback onTap;

  const _FlagRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: value ? AppColors.accent : Colors.transparent,
                border: Border.all(
                  color: value ? AppColors.accent : AppColors.borderColor,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.txt.body)),
          ],
        ),
      ),
    );
  }
}
