import 'package:flutter/material.dart';

import '../../core/models/file_entry.dart';
import '../../i18n/strings.g.dart';
import '../../ui/dialogs/dialog.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/theme/app_text_styles.dart';
import '../../ui/theme/app_theme.dart';
import '../../utils/format.dart';
import '../files/status_chip.dart';
import 'compare_diff.dart';
import 'compare_sync_plan.dart';

Future<bool> showCompareSyncDialog(
  BuildContext context,
  CompareSyncPlan plan,
) async {
  final action = t.compare.syncAction;
  final result = await showCustomDialog<String>(
    context: context,
    title: t.compare.syncTitle,
    icon: WaydirIconsRegular.arrowsClockwise,
    iconColor: AppColors.accent,
    width: 560,
    body: CompareSyncSummary(plan: plan),
    actions: plan.isEmpty
        ? [DialogAction(label: t.compare.done, color: AppColors.fgMuted)]
        : [
            DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
            DialogAction(label: action, color: AppColors.accent),
          ],
  );

  return !plan.isEmpty && result == action;
}

class CompareSyncSummary extends StatelessWidget {
  final CompareSyncPlan plan;

  const CompareSyncSummary({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final items = plan.items;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.sourceRoot,
          style: context.txt.caption,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '→ ${plan.destinationRoot}',
          style: context.txt.caption,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        if (plan.isEmpty)
          Text(t.compare.syncNothing, style: context.txt.body)
        else ...[
          if (plan.added.isNotEmpty)
            _SummaryRow(
              status: CompareStatus.unique,
              label: t.compare.syncAdded,
              detail: _join([
                if (plan.addedFiles > 0)
                  t.compare.syncFiles(n: plan.addedFiles),
                if (plan.addedFolders > 0)
                  t.compare.syncFolders(n: plan.addedFolders),
                if (plan.addedBytes > 0) formatBytes(plan.addedBytes),
              ]),
            ),
          if (plan.updated.isNotEmpty)
            _SummaryRow(
              status: CompareStatus.newer,
              label: t.compare.syncUpdated,
              detail: _join([
                t.compare.syncFiles(n: plan.updated.length),
                formatBytes(plan.updatedBytes),
              ]),
            ),
          if (plan.differing.isNotEmpty)
            _SummaryRow(
              status: CompareStatus.differ,
              label: t.compare.syncDiffering,
              detail: _join([
                t.compare.syncFiles(n: plan.differing.length),
                formatBytes(plan.differingBytes),
              ]),
            ),
        ],
        if (plan.skipped.isNotEmpty)
          _SummaryRow(
            status: CompareStatus.older,
            label: t.compare.syncSkipped,
            detail: t.compare.syncFiles(n: plan.skipped.length),
            muted: true,
          ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.bgDivider),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, i) => _ItemRow(result: items[i]),
            ),
          ),
          Container(height: 1, color: AppColors.bgDivider),
          const SizedBox(height: 6),
          Text(
            t.compare.syncTotal(
              files: t.compare.syncFiles(
                n:
                    plan.addedFiles +
                    plan.updated.length +
                    plan.differing.length,
              ),
              size: formatBytes(plan.totalBytes),
            ),
            style: context.txt.captionSmall,
          ),
        ],
      ],
    );
  }

  static String _join(List<String> parts) => parts.join(' · ');
}

String _glyphFor(CompareStatus status) => switch (status) {
  CompareStatus.unique => '+',
  CompareStatus.newer => '↑',
  CompareStatus.older => '↓',
  CompareStatus.differ => '≠',
  CompareStatus.identical => '=',
  CompareStatus.pending => '?',
};

Color _colorFor(CompareStatus status) => switch (status) {
  CompareStatus.unique => AppColors.compareUnique,
  CompareStatus.newer => AppColors.compareNewer,
  CompareStatus.older => AppColors.compareOlder,
  CompareStatus.differ => AppColors.compareSameTime,
  CompareStatus.identical || CompareStatus.pending => AppColors.fgMuted,
};

class _SummaryRow extends StatelessWidget {
  final CompareStatus status;
  final String label;
  final String detail;
  final bool muted;

  const _SummaryRow({
    required this.status,
    required this.label,
    required this.detail,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = muted ? context.txt.bodyMuted : context.txt.body;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Opacity(
            opacity: muted ? 0.5 : 1,
            child: StatusChip(
              glyph: _glyphFor(status),
              color: _colorFor(status),
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(detail, style: style),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final CompareEntryResult result;

  const _ItemRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final folder = result.type == FileItemType.folder;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          StatusChip(
            glyph: _glyphFor(result.status),
            color: _colorFor(result.status),
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folder ? '${result.relativePath}/' : result.relativePath,
              style: context.txt.row,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!folder) ...[
            const SizedBox(width: 12),
            Text(formatBytes(result.entry.size), style: context.txt.muted),
          ],
        ],
      ),
    );
  }
}
