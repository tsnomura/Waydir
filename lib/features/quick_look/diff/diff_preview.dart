import 'package:flutter/material.dart';

import '../../../core/models/file_entry.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/theme/app_text_styles.dart';
import 'diff_runner.dart';

/// Renders an already-successful [TextDiffResult] as a side-by-side diff,
/// tinting each line by [DiffLine.kind]. Dumb renderer only — deciding
/// whether to show this or fall back to Quick Look's normal single-file
/// preview happens one level up, where that fallback is already in scope.
class TextDiffView extends StatelessWidget {
  final FileEntry left;
  final FileEntry right;
  final TextDiffResult result;

  const TextDiffView({
    super.key,
    required this.left,
    required this.right,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 28,
          color: AppColors.bgStatus,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          child: Text(
            '${left.name}  ↔  ${right.name}',
            style: context.txt.caption.copyWith(color: AppColors.fgMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(height: 1, color: AppColors.bgDivider),
        Expanded(
          child: Container(
            color: AppColors.bg,
            child: result.lines.isEmpty
                ? const SizedBox.shrink()
                : Scrollbar(
                    child: ListView.builder(
                      itemCount: result.lines.length,
                      itemBuilder: (context, index) =>
                          _DiffLineRow(line: result.lines[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final DiffLine line;

  const _DiffLineRow({required this.line});

  Color? get _background => switch (line.kind) {
    DiffLineKind.added => AppColors.compareUnique.withValues(alpha: 0.14),
    DiffLineKind.removed => AppColors.danger.withValues(alpha: 0.14),
    DiffLineKind.changed => AppColors.compareDiffer.withValues(alpha: 0.14),
    DiffLineKind.unchanged => null,
  };

  @override
  Widget build(BuildContext context) {
    final style = context.txt.row.copyWith(fontFamily: 'monospace');

    return Container(
      width: double.infinity,
      color: _background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: Text(line.left.isEmpty ? ' ' : line.left, style: style),
            ),
          ),
          Container(width: 1, color: AppColors.bgDivider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: Text(line.right.isEmpty ? ' ' : line.right, style: style),
            ),
          ),
        ],
      ),
    );
  }
}
