import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../../core/settings/settings_registry.dart';
import '../../../core/settings/settings_store.dart';
import '../../../i18n/strings.g.dart';
import '../../../ui/overlays/toast.dart';
import '../preferences_view.dart';

class GeneralPane extends StatefulWidget {
  final PreferenceAnchors anchors;

  const GeneralPane({super.key, required this.anchors});

  @override
  State<GeneralPane> createState() => _GeneralPaneState();
}

class _GeneralPaneState extends State<GeneralPane> {
  late final void Function() _disposeKeyboardSchemeEffect;
  bool _firstKeyboardSchemeRun = true;

  @override
  void initState() {
    super.initState();
    _disposeKeyboardSchemeEffect = effect(() {
      SettingsStore.instance.keyboardScheme.value;
      if (_firstKeyboardSchemeRun) {
        _firstKeyboardSchemeRun = false;

        return;
      }
      if (!mounted) return;
      showToast(
        context: context,
        message: t.toast.restartRequired,
        duration: const Duration(seconds: 4),
      );
    });
  }

  @override
  void dispose() {
    _disposeKeyboardSchemeEffect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = SettingsRegistry.instance;
    final restoreSession = registry.byId('general.restoreSession');
    final defaultPath = registry.byId('general.defaultStartingPath');
    final confirmDelete = registry.byId('general.confirmDelete');
    final confirmCopy = registry.byId('general.confirmCopy');
    final confirmMove = registry.byId('general.confirmMove');
    final rememberFolderState = registry.byId('general.rememberFolderState');
    final rememberFolderSort = registry.byId('general.rememberFolderSort');
    final typeAheadBuffer = registry.byId('general.typeAheadBuffer');
    final deleteKeyBehavior = registry.byId('general.deleteKeyBehavior');
    final dragMovesByDefault = registry.byId('general.dragMovesByDefault');
    final keyboardScheme = registry.byId('general.keyboardScheme');
    Widget row(AppSetting<dynamic> setting) {
      return RegistrySettingRow(setting: setting, anchors: widget.anchors);
    }

    return SettingsPaneScaffold(
      children: [
        SettingsSection(
          anchorId: 'general.startup',
          anchors: widget.anchors,
          title: t.preferences.general.startupSection,
          children: [row(restoreSession), row(defaultPath)],
        ),
        SettingsSection(
          anchorId: 'general.folders',
          anchors: widget.anchors,
          title: t.preferences.general.foldersSection,
          children: [
            row(rememberFolderState),
            row(rememberFolderSort),
            row(typeAheadBuffer),
          ],
        ),
        SettingsSection(
          anchorId: 'general.fileOps',
          anchors: widget.anchors,
          title: t.preferences.general.fileOpsSection,
          children: [
            row(deleteKeyBehavior),
            row(confirmDelete),
            row(confirmCopy),
            row(confirmMove),
            row(dragMovesByDefault),
          ],
        ),
        SettingsSection(
          anchorId: 'general.keyboard',
          anchors: widget.anchors,
          title: t.preferences.general.keyboardSection,
          children: [row(keyboardScheme)],
        ),
      ],
    );
  }
}
