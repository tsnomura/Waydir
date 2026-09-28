import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';
import 'package:waydir/ui/icons/waydir_icons.dart';

import '../../../core/open/open_service.dart';
import '../../../core/platform/app_dirs.dart';
import '../../../core/settings/settings_registry.dart';
import '../../../core/terminal/system_fonts.dart';
import '../../../i18n/strings.g.dart';
import '../../panes/shell_store.dart';
import '../../../ui/dialogs/dialog.dart';
import '../../../ui/overlays/toast.dart';
import '../../../ui/theme/app_theme.dart';
import '../../../ui/theme/app_text_styles.dart';
import '../../../ui/widgets/app_modal.dart';
import '../../../ui/widgets/app_text_field.dart';
import '../../quick_look/generators/generator_def.dart';
import '../../quick_look/generators/generator_registry.dart';
import '../../quick_look/generators/generator_runner.dart';
import '../preferences_view.dart';

class QuickLookPane extends StatefulWidget {
  final PreferenceAnchors anchors;

  const QuickLookPane({super.key, required this.anchors});

  @override
  State<QuickLookPane> createState() => _QuickLookPaneState();
}

class _QuickLookPaneState extends State<QuickLookPane> {
  late Future<_GeneratorFilesState> _generatorFiles = _loadGeneratorFiles();

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final families = await SystemFonts.monospaceFamilies();
    if (!mounted) return;
    setState(
      () => SettingsRegistry.instance.refreshQuickLookFontChoices(families),
    );
  }

  Future<_GeneratorFilesState> _loadGeneratorFiles() async {
    final dirPath = await AppDirs.generators();
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    final files = <_GeneratorFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File ||
          p.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      files.add(await _readGeneratorFile(entity));
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return _GeneratorFilesState(dirPath: dirPath, files: files);
  }

  Future<_GeneratorFile> _readGeneratorFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'generator file must contain a JSON object',
        );
      }
      final def = GeneratorDef.fromJson(decoded);

      return _GeneratorFile(path: file.path, def: def, raw: decoded);
    } catch (error) {
      return _GeneratorFile(path: file.path, error: '$error');
    }
  }

  Future<void> _reloadGenerators({bool toast = true}) async {
    await GeneratorRegistry.instance.load();
    await GeneratorRunner.clearCache();
    if (!mounted) return;
    setState(() => _generatorFiles = _loadGeneratorFiles());
    if (toast) {
      showToast(
        context: context,
        message: t.preferences.quickLook.generatorsReloaded,
      );
    }
  }

  String _sanitizeGeneratorId(String id) =>
      id.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  Future<_GeneratorFormValues?> _showGeneratorForm({
    _GeneratorFormValues? initial,
  }) {
    return showDialog<_GeneratorFormValues>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Center(
        child: Material(
          type: MaterialType.transparency,
          child: _GeneratorFormDialog(
            initial: initial,
            onCancel: () => Navigator.of(ctx).pop(),
            onSubmit: (values) => Navigator.of(ctx).pop(values),
          ),
        ),
      ),
    );
  }

  Future<void> _addGenerator(String dirPath) async {
    final result = await _showGeneratorForm();
    if (result == null) return;
    final id = _sanitizeGeneratorId(result.id);
    final path = p.join(dirPath, '$id.json');
    if (File(path).existsSync()) {
      if (!mounted) return;
      showToast(
        context: context,
        message: t.preferences.quickLook.generatorIdTaken(id: id),
      );

      return;
    }
    final json = <String, dynamic>{
      '_help':
          'Preview generator config — see docs/generators.md for the full '
          'guide. JSON has no comment syntax, so this is just a regular '
          'field; Waydir ignores every key starting with "_" when loading, '
          'so these are safe to delete once you know the format.',
      'id': id,
      'extensions': result.extensions,
      '_help_extensions':
          'Lowercase file extensions (no dot) this generator handles, e.g. '
          '["mp4", "mkv", "mov"].',
      'cmd': result.cmd,
      '_help_cmd':
          'The executable to run — must be on PATH, or an '
          'absolute path.',
      'args': <String>[],
      '_help_args':
          'Fill in the exact command-line arguments, e.g. '
          '["-y", "-ss", "%SEEK%", "-i", "%INPUT%", "-frames:v", "1", '
          '"-vf", "scale=640:-1", "%OUTPUT%"]. No shell is involved, so no '
          'quoting/injection concerns. Placeholders substituted in every '
          'element: %INPUT% the source file\'s real path, %OUTPUT% where '
          'to write the result image (must end up with the "outputExt" '
          'extension below), %CACHE% a scratch directory, %SEEK% the '
          'timestamp for the current page as HH:MM:SS.mmm (paging:"time" '
          'only), %POSITION% the current page as a 0-based number, %PAGE% '
          'the current page as a 1-based number.',
      'timeoutSeconds': result.timeoutSeconds,
      '_help_timeoutSeconds':
          'Max seconds before the command is killed and treated as '
          'failed. 1-60, also applies to "probeCmd" below.',
      'outputExt': result.outputExt,
      '_help_outputExt':
          'File extension of the generated image, e.g. "png" or "jpg" — '
          'must match what "args" actually writes to %OUTPUT%.',
      '_help_paging':
          'Optional multi-page support (e.g. a PDF\'s pages, or '
          'evenly-spaced video frames) isn\'t set up here — add a '
          '"paging": "time" or "discrete" key, plus "probeCmd"/"probeArgs" '
          '(a command that prints a plain number to stdout) and, for '
          '"time", "pageCount". Full worked examples for both modes are in '
          'docs/generators.md.',
    };
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await _reloadGenerators(toast: false);
  }

  Future<void> _editGenerator(_GeneratorFile file) async {
    final def = file.def;
    if (def == null) return;
    final result = await _showGeneratorForm(
      initial: _GeneratorFormValues(
        id: def.id,
        extensions: def.extensions.toList()..sort(),
        cmd: def.cmd,
        timeoutSeconds: def.timeout.inSeconds,
        outputExt: def.outputExt,
      ),
    );
    if (result == null) return;
    final raw = Map<String, dynamic>.from(file.raw ?? const {});
    raw['id'] = _sanitizeGeneratorId(result.id);
    raw['extensions'] = result.extensions;
    raw['cmd'] = result.cmd;
    raw['timeoutSeconds'] = result.timeoutSeconds;
    raw['outputExt'] = result.outputExt;
    await File(
      file.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(raw));
    await _reloadGenerators(toast: false);
  }

  Future<void> _editGeneratorJson(String path) {
    return OpenService.openDefault(path);
  }

  void _openGeneratorsFolder(String dirPath) {
    ShellStore.current?.openInNewTab(dirPath);
    Navigator.of(context).pop();
  }

  Future<void> _openGeneratorsGuide() async {
    const url =
        'https://github.com/tsnomura/Waydir/blob/personal/docs/generators.md';
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        url,
      ], mode: ProcessStartMode.detached);
    }
  }

  Future<void> _deleteGenerator(String path, String name) async {
    final result = await showCustomDialog<String>(
      context: context,
      title: t.preferences.quickLook.deleteGeneratorTitle,
      icon: WaydirIconsRegular.warning,
      iconColor: AppColors.danger,
      body: Text(
        t.preferences.quickLook.deleteGeneratorMessage(name: name),
        style: context.txt.body,
      ),
      actions: [
        DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
        DialogAction(
          label: t.preferences.quickLook.deleteGenerator,
          color: AppColors.danger,
        ),
      ],
    );
    if (result != t.preferences.quickLook.deleteGenerator) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    await _reloadGenerators(toast: false);
  }

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final useSystemFont = registry.byId('quickLook.useSystemFont');
    final fontFamily = registry.byId('quickLook.fontFamily');
    final fontSize = registry.byId('quickLook.fontSize');
    final lineHeight = registry.byId('quickLook.lineHeight');
    final showLineNumbers = registry.byId('quickLook.showLineNumbers');
    final relativeLineNumbers = registry.byId('quickLook.relativeLineNumbers');
    final showStatistics = registry.byId('quickLook.showStatistics');
    final wrapLines = registry.byId('quickLook.wrapLines');
    final vimMode = registry.byId('quickLook.vimMode');
    Widget row(AppSetting<dynamic> setting) {
      return RegistrySettingRow(setting: setting, anchors: widget.anchors);
    }

    return SettingsPaneScaffold(
      children: [
        SettingsSection(
          anchorId: 'quickLook.font',
          anchors: widget.anchors,
          title: t.preferences.quickLook.fontSection,
          children: [
            row(useSystemFont),
            SignalBuilder(
              builder: (_) {
                if (useSystemFont.value == true) return const SizedBox.shrink();

                return row(fontFamily);
              },
            ),
            row(fontSize),
            row(lineHeight),
          ],
        ),
        SettingsSection(
          anchorId: 'quickLook.editor',
          anchors: widget.anchors,
          title: t.preferences.quickLook.editorSection,
          children: [
            row(showLineNumbers),
            SignalBuilder(
              builder: (_) {
                if (showLineNumbers.value != true) {
                  return const SizedBox.shrink();
                }

                return row(relativeLineNumbers);
              },
            ),
            row(wrapLines),
            row(vimMode),
            row(showStatistics),
          ],
        ),
        SettingsSection(
          anchorId: 'quickLook.generators',
          anchors: widget.anchors,
          title: t.preferences.quickLook.generatorsSection,
          children: [
            FutureBuilder<_GeneratorFilesState>(
              future: _generatorFiles,
              builder: (context, snapshot) {
                final state = snapshot.data;

                return _GeneratorsRow(
                  state: state,
                  onAdd: state == null
                      ? null
                      : () => _addGenerator(state.dirPath),
                  onReload: () => _reloadGenerators(),
                  onOpenFolder: state == null
                      ? null
                      : () => _openGeneratorsFolder(state.dirPath),
                  onOpenGuide: _openGeneratorsGuide,
                  onEdit: _editGenerator,
                  onEditJson: _editGeneratorJson,
                  onDelete: _deleteGenerator,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _GeneratorFormValues {
  final String id;
  final List<String> extensions;
  final String cmd;
  final int timeoutSeconds;
  final String outputExt;

  const _GeneratorFormValues({
    required this.id,
    required this.extensions,
    required this.cmd,
    required this.timeoutSeconds,
    required this.outputExt,
  });
}

class _GeneratorFormDialog extends StatefulWidget {
  final _GeneratorFormValues? initial;
  final VoidCallback onCancel;
  final ValueChanged<_GeneratorFormValues> onSubmit;

  const _GeneratorFormDialog({
    this.initial,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<_GeneratorFormDialog> createState() => _GeneratorFormDialogState();
}

class _GeneratorFormDialogState extends State<_GeneratorFormDialog> {
  late final TextEditingController _id;
  late final TextEditingController _extensions;
  late final TextEditingController _cmd;
  late final TextEditingController _timeout;
  late final TextEditingController _outputExt;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _id = TextEditingController(text: initial?.id ?? '');
    _extensions = TextEditingController(
      text: initial?.extensions.join(', ') ?? '',
    );
    _cmd = TextEditingController(text: initial?.cmd ?? '');
    _timeout = TextEditingController(
      text: (initial?.timeoutSeconds ?? defaultGeneratorTimeoutSeconds)
          .toString(),
    );
    _outputExt = TextEditingController(text: initial?.outputExt ?? 'png');
    for (final c in [_id, _extensions, _cmd, _timeout, _outputExt]) {
      c.addListener(_revalidate);
    }
    _revalidate();
  }

  @override
  void dispose() {
    _id.dispose();
    _extensions.dispose();
    _cmd.dispose();
    _timeout.dispose();
    _outputExt.dispose();
    super.dispose();
  }

  List<String> _parsedExtensions() => _extensions.text
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();

  void _revalidate() {
    final timeoutText = _timeout.text.trim();
    final valid =
        _id.text.trim().isNotEmpty &&
        _cmd.text.trim().isNotEmpty &&
        _parsedExtensions().isNotEmpty &&
        (timeoutText.isEmpty || int.tryParse(timeoutText) != null);
    if (valid != _valid) setState(() => _valid = valid);
  }

  void _submit() {
    if (!_valid) return;
    final timeoutText = _timeout.text.trim();
    final timeout = timeoutText.isEmpty
        ? defaultGeneratorTimeoutSeconds
        : int.parse(timeoutText).clamp(1, maxGeneratorTimeoutSeconds);
    final outputExtText = _outputExt.text.trim();
    widget.onSubmit(
      _GeneratorFormValues(
        id: _id.text.trim(),
        extensions: _parsedExtensions(),
        cmd: _cmd.text.trim(),
        timeoutSeconds: timeout,
        outputExt: outputExtText.isEmpty ? 'png' : outputExtText,
      ),
    );
  }

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
          Text(label, style: context.txt.fieldLabel),
          const SizedBox(height: 4),
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

    return AppModal(
      icon: WaydirIconsRegular.fileCode,
      title: isEdit
          ? t.preferences.quickLook.editGeneratorTitle
          : t.preferences.quickLook.addGeneratorTitle,
      width: 420,
      padding: const EdgeInsets.all(16),
      onClose: widget.onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            t.preferences.quickLook.generatorIdLabel,
            _id,
            hint: 'video-thumbnail',
            autofocus: true,
          ),
          _field(
            t.preferences.quickLook.generatorExtensionsLabel,
            _extensions,
            hint: 'mp4, mkv, mov',
          ),
          _field(
            t.preferences.quickLook.generatorCmdLabel,
            _cmd,
            hint: 'ffmpeg',
          ),
          _field(
            t.preferences.quickLook.generatorTimeoutLabel,
            _timeout,
            hint: '8',
          ),
          _field(
            t.preferences.quickLook.generatorOutputExtLabel,
            _outputExt,
            hint: 'png',
          ),
          Text(
            t.preferences.quickLook.generatorFormHint,
            style: context.txt.muted,
          ),
          const SizedBox(height: 12),
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
                    label: isEdit
                        ? t.preferences.quickLook.saveGenerator
                        : t.preferences.quickLook.addGenerator,
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

class _HoverLink extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final TextStyle baseStyle;

  const _HoverLink({
    required this.text,
    required this.onTap,
    required this.baseStyle,
  });

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.text.isNotEmpty && widget.onTap != null;
    final color = _hovered ? AppColors.fgAccent : widget.baseStyle.color;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: Text(
          widget.text,
          style: widget.baseStyle.copyWith(
            color: color,
            decoration: enabled && _hovered
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}

class _GeneratorsRow extends StatelessWidget {
  final _GeneratorFilesState? state;
  final VoidCallback? onAdd;
  final VoidCallback? onReload;
  final VoidCallback? onOpenFolder;
  final VoidCallback onOpenGuide;
  final ValueChanged<_GeneratorFile> onEdit;
  final ValueChanged<String> onEditJson;
  final void Function(String path, String name) onDelete;

  const _GeneratorsRow({
    required this.state,
    required this.onAdd,
    required this.onReload,
    required this.onOpenFolder,
    required this.onOpenGuide,
    required this.onEdit,
    required this.onEditJson,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final state = this.state;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.preferences.quickLook.generators,
                  style: context.txt.body,
                ),
                const SizedBox(height: 2),
                Text(
                  t.preferences.quickLook.generatorsHint,
                  style: context.txt.muted,
                ),
                const SizedBox(height: 4),
                _HoverLink(
                  text: state?.dirPath ?? '',
                  onTap: onOpenFolder,
                  baseStyle: context.txt.code.copyWith(
                    color: AppColors.fgMuted,
                  ),
                ),
                const SizedBox(height: 4),
                _HoverLink(
                  text: t.preferences.quickLook.generatorsGuideLink,
                  onTap: onOpenGuide,
                  baseStyle: context.txt.muted,
                ),
                const SizedBox(height: 8),
                if (state == null)
                  Text(
                    t.preferences.quickLook.loadingGenerators,
                    style: context.txt.muted,
                  )
                else if (state.files.isEmpty)
                  Text(
                    t.preferences.quickLook.noGenerators,
                    style: context.txt.muted,
                  )
                else
                  Column(
                    children: [
                      for (final file in state.files)
                        _GeneratorFileRow(
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
              if (onAdd != null)
                SettingsActionButton(
                  icon: WaydirIconsRegular.plus,
                  label: t.preferences.quickLook.addGenerator,
                  onTap: onAdd!,
                ),
              if (onAdd != null && onReload != null) const SizedBox(height: 4),
              if (onReload != null)
                SettingsActionButton(
                  icon: WaydirIconsRegular.arrowClockwise,
                  label: t.preferences.quickLook.reloadGenerators,
                  onTap: onReload!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratorFileRow extends StatelessWidget {
  final _GeneratorFile file;
  final VoidCallback onEdit;
  final VoidCallback onEditJson;
  final void Function(String path, String name) onDelete;

  const _GeneratorFileRow({
    required this.file,
    required this.onEdit,
    required this.onEditJson,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final def = file.def;
    final title = def == null ? p.basename(file.path) : def.id;
    final subtitle = def == null
        ? '${t.preferences.quickLook.invalidGenerator}: ${file.error}'
        : '.${def.extensions.join(', .')} — ${def.cmd}';

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
                : WaydirIconsRegular.fileCode,
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
              label: t.preferences.quickLook.editGenerator,
              onTap: onEdit,
            ),
            const SizedBox(width: 4),
          ],
          SettingsActionButton(
            icon: WaydirIconsRegular.code,
            label: t.preferences.quickLook.editGeneratorJson,
            onTap: onEditJson,
          ),
          const SizedBox(width: 4),
          SettingsActionButton(
            icon: WaydirIconsRegular.trash,
            label: t.preferences.quickLook.deleteGenerator,
            onTap: () => onDelete(file.path, title),
          ),
        ],
      ),
    );
  }
}

class _GeneratorFilesState {
  final String dirPath;
  final List<_GeneratorFile> files;

  const _GeneratorFilesState({required this.dirPath, required this.files});
}

class _GeneratorFile {
  final String path;
  final GeneratorDef? def;
  final Map<String, dynamic>? raw;
  final String? error;

  const _GeneratorFile({required this.path, this.def, this.raw, this.error});
}
