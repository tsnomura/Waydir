import 'dart:async';

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';

import '../../app/launch_args.dart';
import '../../core/database/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/platform_paths.dart';
import '../../core/platform/trash_location.dart';
import '../../core/platform/windows_env_vars.dart';
import '../../core/settings/settings_store.dart';
import '../../core/terminal/pty_session.dart';
import '../../core/terminal/terminal_launch.dart';
import '../compare/compare_controller.dart';
import '../navigation/navigation_store.dart';
import '../operations/operation_store.dart';
import '../tags/tag_path.dart';
import '../../ui/overlays/notification_store.dart';
import '../../i18n/strings.g.dart';
import '../tabs/tabs_store.dart';
import 'pane_dir_publisher.dart';
import 'pane_store.dart';
import 'terminal_cwd_signal.dart';
import 'terminal_layout.dart';
import 'terminal_tab.dart';

class ShellStore {
  /// The single live shell. Set on construction so detached UI (e.g. the
  /// preferences dialog) can open a tab without threading the store through.
  static ShellStore? current;

  final isDual = signal(false);
  final panes = signal<List<PaneStore>>([]);
  final activePaneIndex = signal(0);
  final splitRatio = signal(0.5);
  final terminals = signal<List<TerminalTab>>([]);
  final activeTerminalId = signal<Map<int, int>>({});
  final terminalVisible = signal<List<bool>>([false, false]);
  final terminalHeight = signal<List<double>>([260, 260]);
  final OperationStore operationStore;
  final NotificationStore notificationStore;
  late final CompareController compare;
  final ready = signal(false);

  /// Set by the shell widget to the on-screen rect of the combined pane
  /// area (both panes plus the divider), so [inactivePaneRect] can work out
  /// screen coordinates without this store needing any widget references.
  Rect? Function()? paneAreaRectResolver;

  /// The on-screen area of the pane that is *not* currently active, in
  /// dual-pane mode — e.g. for Quick Look to open there instead of covering
  /// the pane the user is actively working in. Null in single-pane mode, or
  /// if the pane area hasn't been laid out yet.
  Rect? inactivePaneRect() {
    if (!isDual.value) return null;
    final area = paneAreaRectResolver?.call();
    if (area == null) return null;
    final leftWidth = area.width * splitRatio.value;

    return activePaneIndex.value == 0
        ? Rect.fromLTWH(
            area.left + leftWidth,
            area.top,
            area.width - leftWidth,
            area.height,
          )
        : Rect.fromLTWH(area.left, area.top, leftWidth, area.height);
  }

  late final activePane = computed(() {
    final list = panes.value;
    if (list.isEmpty) return null;
    final idx = activePaneIndex.value;
    if (idx < 0 || idx >= list.length) return list.first;

    return list[idx];
  });

  late final activeStore = computed(() {
    return activePane.value?.tabs.activeTab.value.store;
  });

  void Function()? _persistDisposer;
  void Function()? _paneDirDisposer;
  Timer? _tabPersistDebounce;
  int _nextTerminalId = 1;
  String? _cwdSignalDir;
  String? _paneDirRoot;

  ShellStore({required this.operationStore, required this.notificationStore}) {
    current = this;
    compare = CompareController(
      panes: panes,
      isDual: isDual,
      operationStore: operationStore,
    );
    _restoreSession();
    Future.wait([
      TerminalCwdSignal.directory(),
      PaneDirPublisher.directory(),
    ]).then((dirs) {
      final cwdSignalDir = dirs[0];
      final paneDirRoot = dirs[1];
      _cwdSignalDir = cwdSignalDir;
      _paneDirRoot = paneDirRoot;
      Directory(paneDirRoot).createSync(recursive: true);
      TerminalCwdSignal.start(_openFromTerminalSignal);
      _setupPaneDirEffect();
      WindowsEnvVars.persist({
        'WAYDIR_CWD_DIR': cwdSignalDir,
        'WAYDIR_PANE_DIR_ROOT': paneDirRoot,
      });
    });
  }

  /// Keeps `pane_dirs/<slot>.txt` and `pane_dirs/active.txt` in sync with
  /// each pane's current directory, for [PaneDirPublisher].
  void _setupPaneDirEffect() {
    _paneDirDisposer = effect(() {
      final dir = _paneDirRoot;
      if (dir == null) return;
      final list = panes.value;
      final activeIdx = activePaneIndex.value;
      for (var slot = 0; slot < list.length; slot++) {
        final path = list[slot].tabs.activeTab.value.store.currentPath.value;
        PaneDirPublisher.publish(dir, '$slot', path);
        if (slot == activeIdx) {
          PaneDirPublisher.publish(dir, 'active', path);
        }
      }
    });
  }

  /// Opens [path] as a new tab in whichever pane owns terminal [terminalId],
  /// per a `TerminalCwdSignal` write. Falls back to the active pane if the
  /// terminal is no longer around (e.g. its tab was already closed).
  void _openFromTerminalSignal(int terminalId, String path) {
    final terminal = terminals.value.where((t) => t.id == terminalId);
    final slot = terminal.isEmpty
        ? activePaneIndex.value
        : (isDual.value ? terminal.first.originPane : 0);
    final list = panes.value;
    if (slot < 0 || slot >= list.length) return;
    list[slot].tabs.addTab(path);
  }

  void openInNewTab(String path) => activePane.value?.tabs.addTab(path);

  static bool _isRestorablePath(String path) {
    if (isTagPath(path) ||
        isTrashPath(path) ||
        PlatformPaths.isRemoteUri(path) ||
        PlatformPaths.isNetworkPath(path)) {
      return true;
    }
    try {
      return Directory(path).existsSync();
    } catch (e, st) {
      log.warn(
        'shell.restore',
        'restorable path probe failed',
        error: e,
        stack: st,
      );

      return false;
    }
  }

  Future<void> _restoreSession() async {
    try {
      await _buildSession();
    } catch (e, st) {
      log.error('shell.restore', 'Session restore failed', error: e, stack: st);
    }
    if (!ready.value) {
      batch(() {
        panes.value = [
          PaneStore(
            operationStore: operationStore,
            initialPath: PlatformPaths.homePath,
          ),
        ];
        isDual.value = false;
        activePaneIndex.value = 0;
        ready.value = true;
      });
    }
    _wirePersistence();
  }

  Future<void> _buildSession() async {
    final s = SettingsStore.instance;
    final db = s.db;

    final launch = LaunchArgs.options;
    if (launch.opensLocation) {
      _buildLaunchSession(launch);

      return;
    }

    final savedTabs = s.restoreSession.value ? await db.getTabs() : const [];

    String initialPathFor() {
      final configured = s.defaultStartingPath.value.trim();
      if (configured.isNotEmpty && Directory(configured).existsSync()) {
        return configured;
      }

      return PlatformPaths.homePath;
    }

    if (savedTabs.isEmpty) {
      batch(() {
        panes.value = [
          PaneStore(
            operationStore: operationStore,
            initialPath: initialPathFor(),
          ),
        ];
        ready.value = true;
      });
    } else {
      final paneMap = <int, List<String>>{};
      final activeMap = <int, int>{};
      for (final tab in savedTabs) {
        paneMap.putIfAbsent(tab.paneIndex, () => []);
        paneMap[tab.paneIndex]!.add(tab.path);
        if (tab.isActive) {
          activeMap[tab.paneIndex] = tab.tabIndex;
        }
      }

      final restored = <PaneStore>[];
      final maxPane = paneMap.keys.reduce((a, b) => a > b ? a : b);
      for (int i = 0; i <= maxPane; i++) {
        final paths = paneMap[i] ?? [];
        final validPaths = paths.where(_isRestorablePath).toList();
        restored.add(
          PaneStore.fromPaths(
            operationStore: operationStore,
            paths: validPaths.isEmpty ? [PlatformPaths.homePath] : validPaths,
            activeTabIndex: activeMap[i] ?? 0,
          ),
        );
      }

      final wantDual = s.sessionIsDual.value && restored.length >= 2;
      final activeIdx = s.sessionActivePaneIndex.value;
      batch(() {
        panes.value = restored;
        isDual.value = wantDual;
        splitRatio.value = s.sessionSplitRatio.value.clamp(0.2, 0.8);
        activePaneIndex.value = wantDual
            ? activeIdx.clamp(0, restored.length - 1)
            : 0;
        ready.value = true;
      });
    }
  }

  void _buildLaunchSession(LaunchOptions launch) {
    final specs = <TabSpec>[
      for (final folder in launch.folders) TabSpec(folder),
      if (launch.selectPath != null)
        TabSpec(PlatformPaths.parentOf(launch.selectPath!), launch.selectPath),
    ];
    if (specs.isEmpty) specs.add(TabSpec(PlatformPaths.homePath));

    final wantDual = launch.split && specs.length >= 2;
    batch(() {
      if (wantDual) {
        panes.value = [
          PaneStore.fromSpecs(
            operationStore: operationStore,
            specs: [specs.first, ...specs.skip(2)],
          ),
          PaneStore.fromSpecs(
            operationStore: operationStore,
            specs: [specs[1]],
          ),
        ];
        isDual.value = true;
      } else {
        panes.value = [
          PaneStore.fromSpecs(operationStore: operationStore, specs: specs),
        ];
        isDual.value = false;
      }
      activePaneIndex.value = 0;
      ready.value = true;
    });
  }

  void _wirePersistence() {
    final s = SettingsStore.instance;
    _persistDisposer = effect(() {
      panes.value;
      for (final pane in panes.value) {
        pane.tabs.tabs.value;
        pane.tabs.activeIndex.value;
        for (final tab in pane.tabs.tabs.value) {
          tab.store.currentPath.value;
        }
      }
      s.sessionIsDual.value = isDual.value;
      s.sessionSplitRatio.value = splitRatio.value;
      s.sessionActivePaneIndex.value = activePaneIndex.value;
      _scheduleTabPersist();
    });
  }

  void _scheduleTabPersist() {
    _tabPersistDebounce?.cancel();
    _tabPersistDebounce = Timer(
      const Duration(milliseconds: 200),
      _persistTabs,
    );
  }

  Future<void> _persistTabs() async {
    try {
      final db = SettingsStore.instance.db;
      final paneList = panes.value;
      final rows = <SessionTabsCompanion>[];
      for (int p = 0; p < paneList.length; p++) {
        final tabs = paneList[p].tabs.tabs.value;
        final activeIdx = paneList[p].tabs.activeIndex.value;
        for (int t = 0; t < tabs.length; t++) {
          rows.add(
            SessionTabsCompanion.insert(
              paneIndex: p,
              tabIndex: t,
              path: tabs[t].store.currentPath.value,
              isActive: Value(t == activeIdx),
            ),
          );
        }
      }
      await db.replaceTabs(rows);
    } catch (e, st) {
      log.error('shell.persist', 'Session persist failed', error: e, stack: st);
    }
  }

  void toggleDual() {
    if (isDual.value) {
      exitDual();
    } else {
      enterDual();
    }
  }

  void enterDual() {
    if (isDual.value) return;
    final currentPath = activeStore.value!.currentPath.value;
    final secondPane = PaneStore(
      operationStore: operationStore,
      initialPath: currentPath,
    );
    final active = TerminalLayout.reassignForDual(activeTerminalId.value, [
      for (final t in terminals.value) TerminalRef(t.id, t.originPane),
    ]);
    batch(() {
      panes.value = [panes.value.first, secondPane];
      activePaneIndex.value = 0;
      activeTerminalId.value = active;
      isDual.value = true;
    });
  }

  void exitDual() {
    if (!isDual.value) return;
    final closing = panes.value[1];
    final visible = terminalVisible.value;
    final active = TerminalLayout.mergeForSingle(activeTerminalId.value, [
      for (final t in terminals.value) t.id,
    ], activePaneIndex.value);
    batch(() {
      activePaneIndex.value = 0;
      panes.value = [panes.value.first];
      terminalVisible.value = TerminalLayout.mergeVisibilityForSingle(visible);
      activeTerminalId.value = active;
      isDual.value = false;
    });
    closing.dispose();
  }

  void setActivePane(int index) {
    if (index >= 0 && index < panes.value.length) {
      activePaneIndex.value = index;
    }
  }

  /// Swaps just the two panes' *active* tabs (history, selection, scroll
  /// position and all, via [TabsStore.replaceActiveTab]) — every other tab
  /// in each pane stays put. Which pane is active, and each pane's other
  /// tabs, are untouched.
  void swapActiveTabs() {
    if (!isDual.value || panes.value.length < 2) return;
    final tabsA = panes.value[0].tabs;
    final tabsB = panes.value[1].tabs;
    final activeA = tabsA.activeTab.value;
    final activeB = tabsB.activeTab.value;
    tabsA.replaceActiveTab(activeB);
    tabsB.replaceActiveTab(activeA);
  }

  void setSplitRatio(double ratio) {
    splitRatio.value = ratio.clamp(0.2, 0.8);
  }

  List<TerminalTab> terminalsForSlot(int slot) {
    if (!isDual.value) return terminals.value;

    return terminals.value.where((t) => t.originPane == slot).toList();
  }

  TerminalTab? activeTerminalForSlot(int slot) {
    final tabs = terminalsForSlot(slot);
    if (tabs.isEmpty) return null;
    final id = activeTerminalId.value[slot];
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }

    return tabs.first;
  }

  TerminalTab? openTerminal(int slot, String cwd, {TerminalLaunchSpec? spec}) {
    final session = PtySession();
    final id = _nextTerminalId++;
    session.terminal.onTitleChange = (title) {
      _setTerminalLabel(id, title);
    };
    final launch = spec ?? TerminalLaunch.resolve(cwd);
    final signalDir = _cwdSignalDir;
    final paneDirRoot = _paneDirRoot;
    final originPane = isDual.value ? slot : 0;
    final env = <String, String>{'WAYDIR_ORIGIN_PANE': '$originPane'};
    if (signalDir != null) {
      env['WAYDIR_TERMINAL_ID'] = '$id';
      env['WAYDIR_CWD_DIR'] = signalDir;
    }
    if (paneDirRoot != null) {
      env['WAYDIR_PANE_DIR_ROOT'] = paneDirRoot;
    }
    final started = session.start(
      cwd: launch.cwd,
      shell: launch.shell,
      args: launch.args,
      env: env,
      onExit: () => closeTerminalTab(id),
    );
    if (!started) {
      session.dispose();

      return null;
    }
    final tab = TerminalTab(
      id: id,
      originPane: originPane,
      session: session,
      focusNode: FocusNode(debugLabel: 'terminal-tab-$id'),
      cwd: cwd,
      label: _terminalLabel(cwd),
    );
    batch(() {
      terminals.value = [...terminals.value, tab];
      setActiveTerminal(slot, id);
      setTerminalVisible(slot, true);
    });

    return tab;
  }

  void closeTerminalTab(int id) {
    TerminalTab? closing;
    for (final tab in terminals.value) {
      if (tab.id == id) {
        closing = tab;
        break;
      }
    }
    if (closing == null) return;
    final slot = isDual.value ? closing.originPane : 0;
    final nextTabs = terminals.value.where((t) => t.id != id).toList();
    final active = Map<int, int>.from(activeTerminalId.value);
    final visible = [...terminalVisible.value];
    final replacement = TerminalLayout.replacementId(
      [for (final t in terminalsForSlot(slot)) t.id],
      id,
      [for (final t in nextTabs) t.id],
    );
    if (replacement == null) {
      active.remove(slot);
      visible[slot] = false;
    } else {
      active[slot] = replacement;
    }
    batch(() {
      terminals.value = nextTabs;
      activeTerminalId.value = active;
      terminalVisible.value = visible;
    });
    closing.dispose();
  }

  void setActiveTerminal(int slot, int id) {
    TerminalTab? tab;
    for (final candidate in terminals.value) {
      if (candidate.id == id) {
        tab = candidate;
        break;
      }
    }
    if (tab == null) return;
    if (!isDual.value && slot == 0 && tab.originPane == 1) {
      tab.originPane = 0;
      terminals.value = [...terminals.value];
    }
    final active = Map<int, int>.from(activeTerminalId.value);
    active[slot] = id;
    activeTerminalId.value = active;
  }

  void cycleTerminal(int slot, int dir) {
    final tabs = terminalsForSlot(slot);
    if (tabs.isEmpty) return;
    final current = activeTerminalForSlot(slot);
    final currentIndex = current == null ? 0 : tabs.indexOf(current);
    final next = (currentIndex + dir + tabs.length) % tabs.length;
    setActiveTerminal(slot, tabs[next].id);
  }

  void reorderTerminalTab(int slot, int from, int to) {
    final visible = terminalsForSlot(slot);
    if (from < 0 || from >= visible.length) return;
    if (to < 0 || to >= visible.length) return;
    if (from == to) return;

    final reordered = List<TerminalTab>.of(visible);
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);

    var nextVisibleIndex = 0;
    final next = [
      for (final tab in terminals.value)
        if (!isDual.value || tab.originPane == slot)
          reordered[nextVisibleIndex++]
        else
          tab,
    ];
    terminals.value = next;
  }

  void setTerminalVisible(int slot, bool visible) {
    final next = [...terminalVisible.value];
    next[slot] = visible;
    terminalVisible.value = next;
  }

  void setTerminalHeight(int slot, double height) {
    final next = [...terminalHeight.value];
    next[slot] = height;
    terminalHeight.value = next;
  }

  void _setTerminalLabel(int id, String title) {
    final label = title.trim();
    if (label.isEmpty) return;
    final tabs = terminals.value;
    for (final tab in tabs) {
      if (tab.id == id) {
        if (tab.label == label) return;
        tab.label = label;
        terminals.value = [...tabs];

        return;
      }
    }
  }

  String _terminalLabel(String cwd) {
    if (cwd == PlatformPaths.homePath) return '~';
    final name = p.basename(cwd);
    if (name.isNotEmpty) return name;

    return cwd.isEmpty ? t.terminal.title : cwd;
  }

  Iterable<NavigationStore> get allStores sync* {
    for (final pane in panes.value) {
      for (final tab in pane.tabs.tabs.value) {
        yield tab.store;
      }
    }
  }

  void dispose() {
    TerminalCwdSignal.stop();
    _paneDirDisposer?.call();
    _paneDirDisposer = null;
    compare.dispose();
    _persistDisposer?.call();
    _persistDisposer = null;
    _tabPersistDebounce?.cancel();
    for (final tab in terminals.value) {
      tab.dispose();
    }
    terminals.value = const [];
    for (final pane in panes.value) {
      pane.dispose();
    }
  }
}
