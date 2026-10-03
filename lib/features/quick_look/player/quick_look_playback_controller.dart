import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/models/file_entry.dart';
import '../generators/generator_def.dart';
import '../generators/generator_page_controller.dart';
import '../generators/generator_registry.dart';
import '../generators/generator_runner.dart';
import 'audio_stream_probe.dart';
import 'ffplay_player.dart';
import 'player_registry.dart';
import 'playback_math.dart';
import 'quick_look_player.dart';

/// Owns every rule in Quick Look's audio-playback design: auto-play while
/// browsing, debounced cursor/page moves, re-seeking without restarting the
/// player, auto-advancing the shown page from elapsed time, and stopping on
/// every exit (close, file change, compare-diff view, lost focus, minimize).
///
/// [sync] is the single entry point for "what's currently shown changed" —
/// called on every relevant rebuild with the current entry and whether
/// something else (compare-mode diff) is covering the preview right now.
/// It's cheap to call repeatedly: a no-op whenever neither actually changed.
class QuickLookPlaybackController {
  QuickLookPlaybackController({QuickLookPlayer? player})
    : _player = player ?? FfplayPlayer();

  static const _entryDebounce = Duration(milliseconds: 250);
  static const _pageDebounce = Duration(milliseconds: 100);
  static const _advanceInterval = Duration(milliseconds: 300);

  final QuickLookPlayer _player;

  String? _activeKey;
  FileEntry? _pendingEntry;
  GeneratorPageController? _generatorPage;

  double? _duration;
  int? _pageCount;
  final _stopwatch = Stopwatch();
  double _playStartSeconds = 0;

  Timer? _entryTimer;
  Timer? _pageTimer;
  Timer? _advanceTimer;
  int _generation = 0;

  /// Call once per rebuild with the entry currently shown (null when there's
  /// none, or it's a folder/multi-selection) and whether a compare-mode diff
  /// is covering the preview instead. A no-op unless the resulting "is this
  /// playable" key actually changed since the last call.
  void sync(
    FileEntry? entry,
    GeneratorPageController generatorPage, {
    required bool blocked,
  }) {
    final playable =
        !blocked && entry != null && entry.type != FileItemType.folder;
    final key = playable ? entry.realPath : null;
    if (key == _activeKey) return;
    _activeKey = key;
    _generatorPage = playable ? generatorPage : null;
    _restartFor(playable ? entry : null);
  }

  void _restartFor(FileEntry? entry) {
    _generation++;
    _entryTimer?.cancel();
    _pageTimer?.cancel();
    _stopEverything();
    _pendingEntry = entry;
    if (entry == null) return;
    _entryTimer = Timer(_entryDebounce, () => _evaluateAndPlay(entry));
  }

  /// Call right after a user-driven PageUp/PageDown changes
  /// [GeneratorPageController.position] (never for the auto-advance writes
  /// this controller makes itself — those already match what's playing).
  void onManualPageChange() {
    if (_duration == null || _pageCount == null) return;
    final generation = _generation;
    _pageTimer?.cancel();
    _pageTimer = Timer(_pageDebounce, () {
      if (generation != _generation) return;
      final page = _generatorPage?.position.value;
      if (page == null) return;
      _startPlaybackAt(page);
    });
  }

  /// Stops playback without touching [_activeKey] — a lost-focus/minimize
  /// pause never auto-resumes on its own; [sync] only restarts things when
  /// the shown file itself changes.
  void stopForLifecycle() {
    _entryTimer?.cancel();
    _pageTimer?.cancel();
    _generation++;
    _stopEverything();
  }

  void dispose() {
    _generation++;
    _entryTimer?.cancel();
    _pageTimer?.cancel();
    _advanceTimer?.cancel();
    unawaited(_player.stop());
  }

  Future<void> _evaluateAndPlay(FileEntry entry) async {
    if (PlayerRegistry.instance.config == null) return;
    final def = GeneratorRegistry.instance.forExtension(entry.extension);
    if (def == null || def.pagingMode != PagingMode.time) return;
    final generation = _generation;
    final hasAudio = await AudioStreamProbe.hasAudio(entry);
    if (!hasAudio || generation != _generation) return;
    final duration = await GeneratorRunner.probeDurationSeconds(entry);
    if (duration == null || duration <= 0 || generation != _generation) return;
    if (!_resumed) return;
    _duration = duration;
    _pageCount = def.pageCount;
    _startPlaybackAt(_generatorPage?.position.value ?? 0);
  }

  bool get _resumed {
    final state = WidgetsBinding.instance.lifecycleState;

    return state == null || state == AppLifecycleState.resumed;
  }

  void _startPlaybackAt(int page) {
    final duration = _duration;
    final pageCount = _pageCount;
    final entry = _pendingEntry;
    if (duration == null || pageCount == null || entry == null) return;
    _playStartSeconds = startSecondsForPage(
      page: page,
      duration: duration,
      pageCount: pageCount,
    );
    _stopwatch
      ..reset()
      ..start();
    unawaited(_player.play(entry.realPath, _playStartSeconds));
    _advanceTimer?.cancel();
    if (pageCount > 1) {
      _advanceTimer = Timer.periodic(_advanceInterval, (_) => _advancePage());
    }
  }

  void _advancePage() {
    final duration = _duration;
    final pageCount = _pageCount;
    final generatorPage = _generatorPage;
    if (duration == null || pageCount == null || generatorPage == null) return;
    final elapsed =
        _playStartSeconds + _stopwatch.elapsed.inMilliseconds / 1000;
    if (elapsed >= duration) {
      _advanceTimer?.cancel();
      generatorPage.position.value = pageCount - 1;

      return;
    }
    generatorPage.position.value = pageForElapsed(
      elapsedSeconds: elapsed,
      duration: duration,
      pageCount: pageCount,
    );
  }

  void _stopEverything() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _stopwatch.stop();
    _duration = null;
    _pageCount = null;
    unawaited(_player.stop());
  }
}
