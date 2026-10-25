part of '../waydir_shell.dart';

mixin _WaydirActionsMixin on State<WaydirShell>, _WaydirStateBase {
  List<FileEntry> _launcherTargets = const [];

  void _showOpenMenuFor(FileEntry entry, Offset position, VoidCallback done);

  bool _canLaunch(FileEntry entry) =>
      entry.type == FileItemType.file &&
      !entry.isGhost &&
      !FileSystemService.isInsideArchive(entry.realPath) &&
      !PlatformPaths.isRemoteUri(entry.realPath);

  (FileEntry, FileEntry)? _comparePairFor(FileEntry entry) {
    if (!_shell.compare.active.value || !_shell.isDual.value) return null;
    final marked = _markedDiffPair();
    if (marked != null &&
        (entry.realPath == marked.$1.realPath ||
            entry.realPath == marked.$2.realPath)) {
      return marked;
    }

    return _shell.compare.diffPairFor(entry.path);
  }

  Future<bool> _interceptOpen(FileEntry entry) async {
    if (!_canLaunch(entry)) return false;
    final pair = _comparePairFor(entry);
    if (pair != null) {
      final def = LauncherRegistry.instance.defaultForCompare(entry.extension);
      if (def != null) {
        await _runLauncher(
          def,
          left: pair.$1.realPath,
          right: pair.$2.realPath,
        );

        return true;
      }
    }
    final def = LauncherRegistry.instance.defaultForOpen(entry.extension);
    if (def == null) return false;
    await _runLauncher(def, files: [entry.realPath]);

    return true;
  }

  void _openAll(List<FileEntry> entries) {
    final grouped = <LauncherDef, List<String>>{};
    for (final entry in entries) {
      final def = _canLaunch(entry)
          ? LauncherRegistry.instance.defaultForOpen(entry.extension)
          : null;
      if (def == null) {
        _active.onOpen(entry);
      } else {
        grouped.putIfAbsent(def, () => []).add(entry.realPath);
      }
    }
    for (final MapEntry(key: def, value: files) in grouped.entries) {
      unawaited(_runLauncher(def, files: files));
    }
  }

  Future<void> _runLauncher(
    LauncherDef def, {
    List<String> files = const [],
    String? left,
    String? right,
  }) async {
    try {
      await LauncherRunner.run(def, files: files, left: left, right: right);
    } on Exception catch (e, st) {
      log.warn('launchers', 'launcher "${def.id}" failed', error: e, stack: st);
      if (!mounted) return;
      showToast(
        context: context,
        message: t.toast.launcherFailed(name: def.name, error: '$e'),
      );
    }
  }

  List<ContextMenuItem> _launcherItems(List<FileEntry> entries) {
    _launcherTargets = entries;
    if (entries.isEmpty || !entries.every(_canLaunch)) return const [];
    final registry = LauncherRegistry.instance;
    final items = <ContextMenuItem>[];
    if (entries.length == 1 && _comparePairFor(entries.first) != null) {
      for (final def in registry.forCompare(entries.first.extension)) {
        items.add(
          ContextMenuItem(
            icon: WaydirIconsRegular.arrowsLeftRight,
            label: def.name,
            action: 'launcher:${def.id}',
          ),
        );
      }
    }
    for (final def in registry.forOpen(
      entries.first.extension,
      count: entries.length,
    )) {
      if (!entries.every((e) => def.matchesExtension(e.extension))) continue;
      items.add(
        ContextMenuItem(
          icon: WaydirIconsRegular.appWindow,
          label: def.name,
          action: 'launcher:${def.id}',
        ),
      );
    }

    return items;
  }

  void _handleLauncherAction(String id) {
    final def = LauncherRegistry.instance.byId(id);
    if (def == null) return;
    final entries = _launcherTargets.where(_canLaunch).toList();
    if (entries.isEmpty) return;
    if (def.context == LauncherContext.compare) {
      final pair = _comparePairFor(entries.first);
      if (pair == null) return;
      unawaited(
        _runLauncher(def, left: pair.$1.realPath, right: pair.$2.realPath),
      );

      return;
    }
    unawaited(_runLauncher(def, files: [for (final e in entries) e.realPath]));
  }

  Future<String?> _promptArchivePassword(
    String archivePath, {
    required bool retry,
  }) async {
    if (!mounted) return null;
    final password = await showPasswordDialog(
      context,
      title: p.basename(archivePath),
      message: retry
          ? t.password.archiveWrongPassword
          : t.password.archivePrompt,
    );
    if (mounted) _restoreFocus();

    return password;
  }

  Future<bool> _confirmSync(CompareSyncPlan plan) async {
    if (!mounted) return false;
    final confirmed = await showCompareSyncDialog(context, plan);
    if (mounted) _restoreFocus();

    return confirmed;
  }

  Future<bool> _confirmTransfer(
    TaskType type,
    List<String> sources,
    String destination,
  ) async {
    final isCopy = type == TaskType.copy;
    final enabled = isCopy
        ? SettingsStore.instance.confirmCopy.value
        : SettingsStore.instance.confirmMove.value;
    if (!enabled) return true;
    if (sources.isEmpty) return true;
    if (!mounted) return true;

    final count = sources.length;
    final single = count == 1;
    final name = PlatformPaths.fileName(sources.first);
    final String title;
    final String message;
    final String actionLabel;
    if (isCopy) {
      title = t.dialog.confirmCopyTitle;
      message = single
          ? t.dialog.confirmCopySingle(name: name, dest: destination)
          : t.dialog.confirmCopyMultiple(count: count, dest: destination);
      actionLabel = t.dialog.copy;
    } else {
      title = t.dialog.confirmMoveTitle;
      message = single
          ? t.dialog.confirmMoveSingle(name: name, dest: destination)
          : t.dialog.confirmMoveMultiple(count: count, dest: destination);
      actionLabel = t.dialog.move;
    }

    final result = await showCustomDialog<String>(
      context: context,
      title: title,
      icon: isCopy
          ? WaydirIconsRegular.copy
          : WaydirIconsRegular.arrowsLeftRight,
      iconColor: AppColors.accent,
      body: Text(message, style: context.txt.body.copyWith(height: 1.4)),
      actions: [
        DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
        DialogAction(label: actionLabel, color: AppColors.accent),
      ],
    );

    return result == actionLabel;
  }

  Future<void> _confirmAndDelete({
    bool forcePermanent = false,
    bool forceTrash = false,
  }) async {
    final entries = _active.selectedEntries;
    if (entries.isEmpty) return;
    if (_active.isTrashView) {
      _active.deletePermanentlySelectedFromTrash();

      return;
    }
    final hasNetworkPath = entries.any(
      (entry) => PlatformPaths.isNetworkPath(entry.realPath),
    );
    final useTrash = forceTrash && !forcePermanent && !hasNetworkPath;
    if (!SettingsStore.instance.confirmDelete.value) {
      _active.deleteSelected(toTrash: useTrash);

      return;
    }
    final count = entries.length;
    final single = count == 1;
    final String message;
    if (useTrash) {
      message = single
          ? t.dialog.confirmTrashSingle(name: entries.first.name)
          : t.dialog.confirmTrashMultiple(count: count);
    } else {
      message = single
          ? t.dialog.confirmDeleteSingle(name: entries.first.name)
          : t.dialog.confirmDeleteMultiple(count: count);
    }
    final actionLabel = useTrash ? t.dialog.moveToTrash : t.dialog.delete;
    final result = await showCustomDialog<String>(
      context: context,
      title: useTrash
          ? t.dialog.confirmTrashTitle
          : t.dialog.confirmDeleteTitle,
      icon: useTrash
          ? WaydirIconsRegular.trashSimple
          : WaydirIconsRegular.trash,
      iconColor: AppColors.danger,
      body: Text(message, style: context.txt.body.copyWith(height: 1.4)),
      actions: [
        DialogAction(label: t.dialog.cancel, color: AppColors.fgMuted),
        DialogAction(label: actionLabel, color: AppColors.danger),
      ],
    );
    if (result == actionLabel) {
      _active.deleteSelected(toTrash: useTrash);
    }
  }

  void _openPropertiesFromMenu(NavigationStore store) {
    final entries = store.selectedEntries;
    if (entries.isEmpty) {
      _openFolderProperties(store.currentPath.value);

      return;
    }
    if (entries.length == 1) {
      showQuickLook(
        context: context,
        store: store,
        explicitEntry: entries.first,
      ).then((_) => _restoreFocus());

      return;
    }
    showQuickLook(
      context: context,
      store: store,
      useMarkedSelection: true,
      onOpenMenu: _showOpenMenuFor,
    ).then((_) => _restoreFocus());
  }

  void _openFolderProperties(String path) {
    if (path.isEmpty) return;
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    final stat = dir.statSync();
    final entry = FileEntry(
      name: PlatformPaths.fileName(path).isEmpty
          ? path
          : PlatformPaths.fileName(path),
      path: path,
      type: FileItemType.folder,
      size: 0,
      modified: stat.modified,
    );
    showQuickLook(
      context: context,
      store: _active,
      explicitEntry: entry,
    ).then((_) => _restoreFocus());
  }

  List<String> _compressSources() {
    return _active.selectedEntries
        .where((e) => !FileSystemService.isInsideArchive(e.realPath))
        .map((e) => e.realPath)
        .toList();
  }

  String _compressBaseName() {
    final store = _active;
    final entries = store.selectedEntries;
    if (entries.length == 1) {
      final e = entries.first;

      return e.type == FileItemType.folder
          ? e.name
          : p.basenameWithoutExtension(e.name);
    }

    return _sanitizeArchiveBase(
      p.basename(store.currentPath.value),
      store.currentPath.value,
    );
  }

  String _sanitizeArchiveBase(String name, String fullPath) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:]'), '').trim();
    if (cleaned.isNotEmpty) return cleaned;
    final drive = RegExp(r'^([A-Za-z]):').firstMatch(fullPath);
    if (drive != null) return drive.group(1)!;

    return 'archive';
  }

  void _quickCompress(ArchiveFormat format) async {
    final store = _active;
    final sources = _compressSources();
    if (sources.isEmpty) return;
    final dir = await store.resolveForOperation(store.currentPath.value);
    if (dir == null) return;
    final dest = await FileSystemService.uniquePathAsync(
      p.join(dir, '${_compressBaseName()}.${format.extension}'),
    );
    store.operationStore.enqueueCompress(
      sources,
      dest,
      format: format.name,
      level: CompressionLevel.normal.name,
    );
  }

  Future<void> _compressWithOptions() async {
    final store = _active;
    final sources = _compressSources();
    if (sources.isEmpty) return;
    final dir = store.currentPath.value;
    final req = await showCompressDialog(
      context: context,
      defaultBaseName: _compressBaseName(),
      destinationDir: dir,
    );
    if (req == null) return;
    final physicalDir = await store.resolveForOperation(dir);
    if (physicalDir == null) return;
    final dest = await FileSystemService.uniquePathAsync(
      p.join(physicalDir, req.fileName),
    );
    store.operationStore.enqueueCompress(
      sources,
      dest,
      format: req.format.name,
      level: req.level.name,
    );
  }

  void _multiRename(NavigationStore store) async {
    final entries = store.selectedEntries;
    if (entries.isEmpty) return;
    if (store.isTrashView) {
      showToast(context: context, message: t.toast.multiRenameTrashBlocked);

      return;
    }
    final result = await showMultiRenameDialog(
      context: context,
      entries: entries,
    );
    if (result == null || result.renames.isEmpty) {
      _restoreFocus();

      return;
    }
    var cancelled = false;
    final task = store.operationStore.beginPluginTask(
      title: t.multiRename.title,
      totalFiles: result.renames.length,
      onCancel: () => cancelled = true,
    );
    store.operationStore.updatePluginTask(
      task.id,
      progress: 0,
      processedFiles: 0,
      totalFiles: result.renames.length,
      currentFile: t.tasks.status.scanning,
    );
    try {
      final outcome = await store.multiRename(
        result.renames
            .map((r) => (path: r.oldPath, newName: r.newName))
            .toList(),
        isCancelled: () => cancelled,
        onProgress: (processed, total, currentName) {
          store.operationStore.updatePluginTask(
            task.id,
            progress: total == 0 ? 0 : processed / total,
            processedFiles: processed,
            totalFiles: total,
            currentFile: currentName,
          );
        },
      );
      store.operationStore.finishPluginTask(
        task.id,
        success: true,
        cancelled: cancelled,
        error: outcome.failed == 0 ? '' : _multiRenameDetails(outcome),
      );
      if (mounted && !cancelled) _showMultiRenameToast(outcome);
    } catch (e) {
      store.operationStore.finishPluginTask(
        task.id,
        success: false,
        cancelled: cancelled,
        error: e.toString(),
      );
      if (mounted && !cancelled) {
        showToast(
          context: context,
          message: t.toast.renameError(message: e),
        );
      }
    } finally {
      _restoreFocus();
    }
  }

  void _showMultiRenameToast(MultiRenameOutcome outcome) {
    if (outcome.blocked) {
      showToast(context: context, message: t.toast.multiRenameTrashBlocked);

      return;
    }
    if (outcome.failed == 0) {
      showToast(
        context: context,
        message: t.toast.multiRenameSuccess(count: outcome.succeeded),
      );

      return;
    }
    final details = _multiRenameDetails(outcome);
    showToast(
      context: context,
      message: t.toast.multiRenamePartial(
        succeeded: outcome.succeeded,
        total: outcome.total,
        details: details,
      ),
    );
  }

  String _multiRenameDetails(MultiRenameOutcome outcome) {
    final parts = <String>[];
    if (outcome.collision > 0) {
      parts.add(t.toast.multiRenameCollisions(count: outcome.collision));
    }
    if (outcome.invalid > 0) {
      parts.add(t.toast.multiRenameInvalid(count: outcome.invalid));
    }
    if (outcome.other > 0) {
      parts.add(t.toast.multiRenameOtherErrors(count: outcome.other));
    }

    return parts.join(', ');
  }

  void _extractSelected({
    required bool toOwnFolder,
    bool toOtherPane = false,
  }) async {
    final store = _active;
    final NavigationStore target;
    if (toOtherPane) {
      final panes = _shell.panes.value;
      if (!_shell.isDual.value || panes.length < 2) return;
      target =
          panes[1 - _shell.activePaneIndex.value].tabs.activeTab.value.store;
    } else {
      target = store;
    }
    final base = await target.resolveForOperation(target.currentPath.value);
    if (base == null) return;
    final archives = store.selectedEntries
        .where(
          (e) =>
              e.type == FileItemType.file &&
              ArchivePath.isArchiveName(e.name) &&
              !FileSystemService.isInsideArchive(e.realPath),
        )
        .toList();
    if (archives.isEmpty) return;
    final passwords = await ArchivePasswords.collect(
      archives.map((e) => e.realPath),
    );
    if (passwords == null) return;

    if (toOwnFolder) {
      for (final entry in archives) {
        final dest = await FileSystemService.uniquePathAsync(
          p.join(base, FileSystemService.archiveBaseName(entry.name)),
          isFolder: true,
        );
        store.operationStore.enqueueExtract(
          [entry.realPath],
          dest,
          passwords: {entry.realPath: ?passwords[entry.realPath]},
        );
      }
    } else {
      store.operationStore.enqueueExtract(
        archives.map((e) => e.realPath).toList(),
        base,
        passwords: passwords,
      );
    }
  }

  void _openPreferences() {
    showPreferencesDialog(context).then((_) {
      if (!mounted) return;
      _restoreFocus();
    });
  }

  void _openHelp() {
    showHelpDialog(context).then((_) {
      if (!mounted) return;
      _restoreFocus();
    });
  }

  void _openQuickLook() {
    if (_isModalRouteOnTop()) return;
    showQuickLook(
      context: context,
      store: _active,
      diffPair: _compareDiffResolver(),
      onOpenMenu: _showOpenMenuFor,
    ).then((_) => _restoreFocus());
  }

  void _openQuickLookMarked() {
    if (_isModalRouteOnTop()) return;
    if (_active.selectedPaths.value.isEmpty) return;
    showQuickLook(
      context: context,
      store: _active,
      useMarkedSelection: true,
      diffPair: _compareDiffResolver(),
      onOpenMenu: _showOpenMenuFor,
    ).then((_) => _restoreFocus());
  }

  QuickLookDiffResolver? _compareDiffResolver() {
    if (!_shell.compare.active.value || !_shell.isDual.value) return null;
    final marked = _markedDiffPair();

    return (entry) {
      if (entry == null) return null;
      final pair =
          marked != null &&
              (entry.realPath == marked.$1.realPath ||
                  entry.realPath == marked.$2.realPath)
          ? marked
          : _shell.compare.diffPairFor(entry.path);
      if (pair == null) return null;
      if (PlatformPaths.isRemoteUri(pair.$1.realPath) ||
          PlatformPaths.isRemoteUri(pair.$2.realPath)) {
        return null;
      }

      return pair;
    };
  }

  (FileEntry, FileEntry)? _markedDiffPair() {
    if (!_shell.compare.active.value || !_shell.isDual.value) return null;
    final panes = _shell.panes.value;
    if (panes.length < 2) return null;
    final leftEntries = panes[0].tabs.activeTab.value.store.selectedEntries;
    final rightEntries = panes[1].tabs.activeTab.value.store.selectedEntries;
    if (leftEntries.length != 1 || rightEntries.length != 1) return null;
    final left = leftEntries.first;
    final right = rightEntries.first;
    if (left.type != FileItemType.file || right.type != FileItemType.file) {
      return null;
    }

    return (left, right);
  }

  void _openSelectPattern() {
    if (_isModalRouteOnTop()) return;
    final store = _active;
    showSelectPatternDialog(context).then((pattern) {
      if (!mounted) return;
      _restoreFocus();
      if (pattern == null) return;
      store.selectByPattern(pattern);
    });
  }

  Future<void> _saveSelectionToFile() async {
    if (_isModalRouteOnTop()) return;
    final store = _active;
    final names = store.selectedNamesForFile();
    if (names.isEmpty) return;
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: t.selectionFile.saveTitle,
        fileName: 'selection.txt',
        initialDirectory: store.currentPath.value,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        lockParentWindow: true,
      );
      if (!mounted) return;
      _restoreFocus();
      if (path == null) return;
      await File(path).writeAsString('${names.join('\n')}\n');
      if (!mounted) return;
      showToast(
        context: context,
        message: t.toast.selectionSaved(count: names.length, path: path),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(
        context: context,
        message: t.toast.selectionFileError(message: e.toString()),
      );
    }
  }

  Future<void> _loadSelectionFromFile() async {
    if (_isModalRouteOnTop()) return;
    final store = _active;
    if (store.visibleFiles.value.isEmpty) return;
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: t.selectionFile.loadTitle,
        initialDirectory: store.currentPath.value,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        lockParentWindow: true,
      );
      if (!mounted) return;
      _restoreFocus();
      final path = result?.files.single.path;
      if (path == null) return;
      final lines = await File(path).readAsLines();
      final count = store.selectNamesFromFile(lines);
      if (!mounted) return;
      showToast(
        context: context,
        message: count == 0
            ? t.toast.selectionLoadEmpty
            : t.toast.selectionLoaded(count: count),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(
        context: context,
        message: t.toast.selectionFileError(message: e.toString()),
      );
    }
  }

  Future<void> _dualPaneTransfer(
    NavigationStore store, {
    required bool move,
  }) async {
    final activeIdx = _shell.activePaneIndex.value;
    final otherStore =
        _shell.panes.value[1 - activeIdx].tabs.activeTab.value.store;
    final otherPath = otherStore.currentPath.value;
    if (isTagPath(otherPath)) {
      final id = tagIdFromPath(otherPath);
      final paths = _dualPaneEntries(store).map((e) => e.path).toList();
      if (id != null && paths.isNotEmpty) await otherStore.addTag(paths, id);

      return;
    }
    final sources = _dualPaneSources(store);
    if (sources.isEmpty) return;
    final dest = await otherStore.resolveForOperation(otherPath);
    if (dest == null) return;
    if (move) {
      _operationStore.enqueueMove(sources, dest);
    } else {
      _operationStore.enqueueCopy(sources, dest);
    }
  }

  List<FileEntry> _dualPaneEntries(NavigationStore store) {
    final entries = store.selectedEntries;
    if (entries.isNotEmpty) return entries;
    final entry = store.cursorEntry.value;
    if (entry != null && !entry.isGhost) return [entry];

    return const [];
  }

  List<String> _dualPaneSources(NavigationStore store) =>
      _dualPaneEntries(store).map((e) => e.realPath).toList();

  void _copySelectedWithToast(NavigationStore store) {
    store.copySelected();
    final count = store.selectedPaths.value.length;
    if (count > 0) {
      showToast(
        context: context,
        message: t.toast.copiedItems(count: count),
      );
    }
  }

  void _cutSelectedWithToast(NavigationStore store) {
    store.cutSelected();
    final count = store.selectedPaths.value.length;
    if (count > 0) {
      showToast(
        context: context,
        message: t.toast.cutItems(count: count),
      );
    }
  }

  Future<void> _duplicateSelected(NavigationStore store) async {
    if (store.isTrashView) return;
    final entries = _dualPaneEntries(store);
    if (entries.isEmpty) return;
    final dest = await store.resolveForOperation(store.currentPath.value);
    if (dest == null) return;
    final sources = entries.map((e) => e.realPath).toList();
    _operationStore.enqueueDuplicate(sources, dest);
    if (!mounted) return;
    showToast(
      context: context,
      message: t.toast.duplicatedItems(count: entries.length),
    );
  }

  void _toggleViewMode() {
    final mode = SettingsStore.instance.fileViewMode;
    mode.value = switch (mode.value) {
      'list' => 'tree',
      'tree' => 'grid',
      _ => 'list',
    };
  }

  void _setViewMode(String mode) {
    SettingsStore.instance.fileViewMode.value = mode;
  }

  void _toggleSidebarCollapsed() {
    final s = SettingsStore.instance.sidebarCollapsed;
    final expanding = s.value;
    s.value = !s.value;
    if (expanding) SidebarKeyboardFocus.requestFocus();
  }

  void _newTabHere() {
    _shell.activePane.value!.tabs.addTab(_active.currentPath.value);
  }

  void _closeActiveTab() {
    final tabsStore = _shell.activePane.value!.tabs;
    if (tabsStore.tabs.value.length > 1) {
      tabsStore.closeTab(tabsStore.activeTab.value.id);

      return;
    }
    final totalTabs = _shell.panes.value.fold<int>(
      0,
      (total, pane) => total + pane.tabs.tabs.value.length,
    );
    if (Platform.isMacOS && totalTabs <= 1) appWindow.close();
  }

  void _selectNextTab() {
    final tabsStore = _shell.activePane.value!.tabs;
    final count = tabsStore.tabs.value.length;
    tabsStore.selectTab((tabsStore.activeIndex.value + 1) % count);
  }

  void _selectPrevTab() {
    final tabsStore = _shell.activePane.value!.tabs;
    final count = tabsStore.tabs.value.length;
    tabsStore.selectTab((tabsStore.activeIndex.value - 1 + count) % count);
  }

  void _renameOrMultiRename(NavigationStore store) {
    if (store.selectedCount.value >= 2) {
      _multiRename(store);
    } else {
      store.startRename();
    }
  }
}
