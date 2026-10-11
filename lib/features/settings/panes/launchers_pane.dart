import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../../core/open/open_service.dart';
import '../../../core/platform/app_dirs.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/dialogs/dialog.dart';
import '../../../ui/overlays/toast.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/theme/app_text_styles.dart';
import '../../../ui/widgets/app_modal.dart';
import '../../../ui/widgets/app_text_field.dart';
import '../../../ui/widgets/app_toggle_chip.dart';
import '../../launchers/launcher_def.dart';
import '../../launchers/launcher_registry.dart';
import '../../panes/shell_store.dart';
import '../preferences_view.dart';

class LaunchersPane extends StatefulWidget {
  final PreferenceAnchors anchors;

  const LaunchersPane({super.key, required this.anchors});

  @override
  State<LaunchersPane> createState() => _LaunchersPaneState();
}

class _LaunchersPaneState extends State<LaunchersPane> {
  late Future<_LauncherFilesState> _files = _loadFiles();

  Future<_LauncherFilesState> _loadFiles() async {
    final dirPath = await AppDirs.launchers();
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    final files = <_LauncherFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File ||
          p.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      files.add(await _readFile(entity));
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return _LauncherFilesState(dirPath: dirPath, files: files);
  }

  Future<_LauncherFile> _readFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('launcher file must contain a JSON object');
      }

      return _LauncherFile(
        path: file.path,
        def: LauncherDef.fromJson(decoded),
        raw: decoded,
      );
    } catch (error) {
      return _LauncherFile(path: file.path, error: '$error');
    }
  }

  Future<void> _reload({bool toast = true}) async {
    await LauncherRegistry.instance.load();
    if (!mounted) return;
    setState(() => _files = _loadFiles());
    if (toast) {
      showToast(context: context, message: t.preferences.launchers.reloaded);
    }
  }

  String _sanitizeId(String id) =>
      id.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  Future<_LauncherFormValues?> _showForm({_LauncherFormValues? initial}) {
    return showDialog<_LauncherFormValues>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: _LauncherFormDialog(
            initial: initial,
            onCancel: () => Navigator.of(ctx).pop(),
            onSubmit: (values) => Navigator.of(ctx).pop(values),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _applyValues(
    Map<String, dynamic> json,
    _LauncherFormValues values,
  ) {
    json['id'] = _sanitizeId(values.id);
    json['name'] = values.name;
    json['context'] = values.context == LauncherContext.compare
        ? 'compare'
        : 'open';
    if (values.extensions.isEmpty) {
      json.remove('extensions');
    } else {
      json['extensions'] = values.extensions;
    }
    json['cmd'] = values.cmd;
    json['args'] = values.args;
    json['default'] = values.isDefault;

    return json;
  }

  Future<void> _write(String path, Map<String, dynamic> json) => File(
    path,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(json));

  Future<void> _add(String dirPath) async {
    final result = await _showForm();
    if (result == null) return;
    final id = _sanitizeId(result.id);
    final path = p.join(dirPath, '$id.json');
    if (File(path).existsSync()) {
      if (!mounted) return;
      showToast(
        context: context,
        message: t.preferences.launchers.idTaken(id: id),
      );

      return;
    }
    await _write(path, _applyValues(<String, dynamic>{}, result));
    await _reload(toast: false);
  }

  Future<void> _edit(_LauncherFile file) async {
    final def = file.def;
    if (def == null) return;
    final result = await _showForm(
      initial: _LauncherFormValues(
        id: def.id,
        name: def.name,
        context: def.context,
        extensions: def.extensions.toList()..sort(),
        cmd: def.cmd,
        args: def.args,
        isDefault: def.isDefault,
      ),
    );
    if (result == null) return;
    await _write(
      file.path,
      _applyValues(Map<String, dynamic>.from(file.raw ?? const {}), result),
    );
    await _reload(toast: false);
  }

  void _openFolder(String dirPath) {
    ShellStore.current?.openInNewTab(dirPath);
    Navigator.of(context).pop();
  }

  Future<void> _delete(String path, String name) async {
    final result = await showCustomDialog<String>(
      context: context,
      title: t.preferences.launchers.deleteTitle,
      icon: WaydirIconsRegular.warning,
      iconColor: AppColors.danger,
      body: Text(
        t.preferences.launchers.deleteMessage(name: name),
        style: context.txt.body,
      ),
      actions: [
        DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
        DialogAction(
          label: t.preferences.launchers.delete,
          color: AppColors.danger,
        ),
      ],
    );
    if (result != t.preferences.launchers.delete) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    await _reload(toast: false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPaneScaffold(
      children: [
        SettingsSection(
          anchorId: 'launchers.list',
          anchors: widget.anchors,
          title: t.preferences.launchers.section,
          children: [
            FutureBuilder<_LauncherFilesState>(
              future: _files,
              builder: (context, snapshot) {
                final state = snapshot.data;

                return _LaunchersRow(
                  state: state,
                  onAdd: state == null ? null : () => _add(state.dirPath),
                  onReload: () => _reload(),
                  onOpenFolder: state == null
                      ? null
                      : () => _openFolder(state.dirPath),
                  onEdit: _edit,
                  onEditJson: OpenService.openDefault,
                  onDelete: _delete,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _LauncherFormValues {
  final String id;
  final String name;
  final LauncherContext context;
  final List<String> extensions;
  final String cmd;
  final List<String> args;
  final bool isDefault;

  const _LauncherFormValues({
    required this.id,
    required this.name,
    required this.context,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.isDefault,
  });
}

class _LauncherFormDialog extends StatefulWidget {
  final _LauncherFormValues? initial;
  final VoidCallback onCancel;
  final ValueChanged<_LauncherFormValues> onSubmit;

  const _LauncherFormDialog({
    this.initial,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<_LauncherFormDialog> createState() => _LauncherFormDialogState();
}

class _LauncherFormDialogState extends State<_LauncherFormDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _extensions;
  late final TextEditingController _cmd;
  late final TextEditingController _args;
  late LauncherContext _context;
  late bool _isDefault;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _id = TextEditingController(text: initial?.id ?? '');
    _name = TextEditingController(text: initial?.name ?? '');
    _extensions = TextEditingController(
      text: initial?.extensions.join(', ') ?? '',
    );
    _cmd = TextEditingController(text: initial?.cmd ?? '');
    _args = TextEditingController(text: initial?.args.join('\n') ?? '%FILE%');
    _context = initial?.context ?? LauncherContext.open;
    _isDefault = initial?.isDefault ?? false;
    for (final c in [_id, _name, _extensions, _cmd, _args]) {
      c.addListener(_revalidate);
    }
    _revalidate();
  }

  @override
  void dispose() {
    for (final c in [_id, _name, _extensions, _cmd, _args]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _parsedExtensions() => _extensions.text
      .split(',')
      .map((e) => e.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
      .where((e) => e.isNotEmpty)
      .toList();

  List<String> _parsedArgs() => _args.text
      .split('\n')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();

  void _revalidate() {
    final valid =
        _id.text.trim().isNotEmpty &&
        _cmd.text.trim().isNotEmpty &&
        (_context == LauncherContext.compare || _parsedExtensions().isNotEmpty);
    if (valid != _valid) setState(() => _valid = valid);
  }

  void _setContext(LauncherContext value) {
    setState(() => _context = value);
    _revalidate();
  }

  void _submit() {
    if (!_valid) return;
    final name = _name.text.trim();
    widget.onSubmit(
      _LauncherFormValues(
        id: _id.text.trim(),
        name: name.isEmpty ? _id.text.trim() : name,
        context: _context,
        extensions: _parsedExtensions(),
        cmd: _cmd.text.trim(),
        args: _parsedArgs(),
        isDefault: _isDefault,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: context.txt.fieldLabel),
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          AppTextField(
            controller: controller,
            hintText: hint,
            autofocus: autofocus,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final s = t.preferences.launchers;
    final compare = _context == LauncherContext.compare;

    return AppModal(
      icon: WaydirIconsRegular.appWindow,
      title: isEdit ? s.editTitle : s.addTitle,
      width: 460,
      padding: const EdgeInsets.all(16),
      onClose: widget.onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(s.idLabel, _id, hint: 'f3d-step', autofocus: true),
          _field(s.nameLabel, _name, hint: 'View in f3d (STEP)'),
          _label(s.contextLabel),
          Row(
            children: [
              Expanded(
                child: AppToggleChip(
                  label: s.contextOpen,
                  selected: !compare,
                  onTap: () => _setContext(LauncherContext.open),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppToggleChip(
                  label: s.contextCompare,
                  selected: compare,
                  onTap: () => _setContext(LauncherContext.compare),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _field(
            s.extensionsLabel,
            _extensions,
            hint: compare ? s.extensionsCompareHint : 'step, stp',
          ),
          _field(s.cmdLabel, _cmd, hint: 'f3d'),
          _label(s.argsLabel),
          TextField(
            controller: _args,
            minLines: 3,
            maxLines: 6,
            style: context.txt.code,
            decoration: appInputDecoration(
              hintText: compare ? '%LEFT%\n%RIGHT%' : '%FILE%',
            ),
          ),
          const SizedBox(height: 6),
          Text(s.placeholders, style: context.txt.muted),
          const SizedBox(height: 12),
          Row(
            children: [
              SettingsToggle(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(s.defaultLabel, style: context.txt.body)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DialogButton(
                label: t.dialog.cancel,
                color: AppColors.fgMuted,
                onTap: widget.onCancel,
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: _valid ? 1.0 : 0.4,
                child: IgnorePointer(
                  ignoring: !_valid,
                  child: DialogButton(
                    label: isEdit ? s.save : s.add,
                    color: AppColors.accent,
                    onTap: _submit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LaunchersRow extends StatelessWidget {
  final _LauncherFilesState? state;
  final VoidCallback? onAdd;
  final VoidCallback onReload;
  final VoidCallback? onOpenFolder;
  final ValueChanged<_LauncherFile> onEdit;
  final ValueChanged<String> onEditJson;
  final void Function(String path, String name) onDelete;

  const _LaunchersRow({
    required this.state,
    required this.onAdd,
    required this.onReload,
    required this.onOpenFolder,
    required this.onEdit,
    required this.onEditJson,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final state = this.state;
    final s = t.preferences.launchers;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: context.txt.body),
                const SizedBox(height: 2),
                Text(s.hint, style: context.txt.muted),
                const SizedBox(height: 4),
                if (state != null)
                  GestureDetector(
                    onTap: onOpenFolder,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        state.dirPath,
                        style: context.txt.code.copyWith(
                          color: AppColors.fgMuted,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(s.placeholders, style: context.txt.muted),
                const SizedBox(height: 8),
                if (state == null)
                  Text(s.loading, style: context.txt.muted)
                else if (state.files.isEmpty)
                  Text(s.empty, style: context.txt.muted)
                else
                  Column(
                    children: [
                      for (final file in state.files)
                        _LauncherFileRow(
                          file: file,
                          onEdit: () => onEdit(file),
                          onEditJson: () => onEditJson(file.path),
                          onDelete: onDelete,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onAdd != null) ...[
                SettingsActionButton(
                  icon: WaydirIconsRegular.plus,
                  label: s.add,
                  onTap: onAdd!,
                ),
                const SizedBox(height: 4),
              ],
              SettingsActionButton(
                icon: WaydirIconsRegular.arrowClockwise,
                label: s.reload,
                onTap: onReload,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LauncherFileRow extends StatelessWidget {
  final _LauncherFile file;
  final VoidCallback onEdit;
  final VoidCallback onEditJson;
  final void Function(String path, String name) onDelete;

  const _LauncherFileRow({
    required this.file,
    required this.onEdit,
    required this.onEditJson,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = t.preferences.launchers;
    final def = file.def;
    final title = def == null ? p.basename(file.path) : def.name;
    final String subtitle;
    if (def == null) {
      subtitle = '${s.invalid}: ${file.error}';
    } else {
      final tags = [
        if (def.context == LauncherContext.compare) s.compareBadge,
        if (def.isDefault) s.defaultBadge,
        if (def.extensions.isNotEmpty) '.${def.extensions.join(', .')}',
      ];
      subtitle = '${tags.join(' · ')} — ${def.cmd} ${def.args.join(' ')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Icon(
            def == null
                ? WaydirIconsRegular.warning
                : def.context == LauncherContext.compare
                ? WaydirIconsRegular.arrowsLeftRight
                : WaydirIconsRegular.appWindow,
            size: 14,
            color: def == null ? AppColors.warning : AppColors.fgMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.txt.body,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.txt.captionSmall.copyWith(
                    color: AppColors.fgMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (def != null) ...[
            SettingsActionButton(
              icon: WaydirIconsRegular.pencilSimple,
              label: s.edit,
              onTap: onEdit,
            ),
            const SizedBox(width: 4),
          ],
          SettingsActionButton(
            icon: WaydirIconsRegular.code,
            label: s.editJson,
            onTap: onEditJson,
          ),
          const SizedBox(width: 4),
          SettingsActionButton(
            icon: WaydirIconsRegular.trash,
            label: s.delete,
            onTap: () => onDelete(file.path, title),
          ),
        ],
      ),
    );
  }
}

class _LauncherFilesState {
  final String dirPath;
  final List<_LauncherFile> files;

  const _LauncherFilesState({required this.dirPath, required this.files});
}

class _LauncherFile {
  final String path;
  final LauncherDef? def;
  final Map<String, dynamic>? raw;
  final String? error;

  const _LauncherFile({required this.path, this.def, this.raw, this.error});
}
