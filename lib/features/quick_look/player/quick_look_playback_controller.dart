import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:signals/signals.dart';

import '../../../core/models/file_entry.dart';
import '../generators/generator_def.dart';
import '../generators/generator_page_controller.dart';
import '../generators/generator_registry.dart';
import '../generators/generator_runner.dart';
import 'audio_stream_probe.dart';
import 'ffplay_player.dart';
import 'in_app_video.dart';
import 'player_registry.dart';
import 'playback_math.dart';
import 'quick_look_player.dart';

enum PlaybackState { idle, playing, paused }

/// Owns every rule in Quick Look's playback design: auto-play while browsing,
/// debounced cursor/page moves, re-seeking without restarting the player,
/// auto-advancing the shown page from elapsed time, stopping on every exit
/// (close, file change, compare-diff view), pausing on lost focus or
/// minimize, and the click-to-toggle pause the preview offers. A pause only
/// ever ends by the user's click; focus coming back leaves it paused. An
/// in-app video is never paused in its engine: a pause releases the player
/// and cues a fresh one at the same point, and resuming plays that one.
/// Audio goes through the user-configured external player; local videos go
/// through the in-app [InAppVideoPlayer] so picture and sound share one
/// engine.
///
/// [sync] is the single entry point for "what's currently shown changed" —
/// called on every relevant rebuild with the current entry and whether
/// something else (compare-mode diff) is covering the preview right now.
/// It's cheap to call repeatedly: a no-op whenever neither actually changed.
class QuickLookPlaybackController {
  QuickLookPlaybackController({
    QuickLookPlayer? player,
    InAppVideoPlayer? video,
  }) : _player = player ?? FfplayPlayer(),
       _video = video ?? InAppVideoPlayer();

  static const _entryDebounce = Duration(milliseconds: 250);
  static const _pageDebounce = Duration(milliseconds: 100);
  static const _advanceInterval = Duration(milliseconds: 300);

  final QuickLookPlayer _player;
  final InAppVideoPlayer _video;
  bool _inAppVideo = false;

  QuickLookPlayer get _activePlayer => _inAppVideo ? _video : _player;

  InAppVideoPlayer get video => _video;

  final state = signal(PlaybackState.idle);

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

  double _resumeAt = 0;
  bool _startPaused = false;

  /// Call once per rebuild with the entry currently shown (null when there's
  /// none, or it's a folder/multi-selection) and whether a compare-mode diff
  /// is covering the preview instead. A no-op unless the resulting "is this
  /// playable" key actually changed since the last call.
  void sync(
    FileEntry? entry,
    GeneratorPageController generatorPage, {
    required bool blocked,
    int generation = 0,
  }) {
    final playable =
        !blocked && entry != null && entry.type != FileItemType.folder;
    final key = playable ? '${entry.realPath}#$generation' : null;
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
    _startPaused = false;
    _pendingEntry = entry;
    if (entry == null) return;
    _entryTimer = Timer(_entryDebounce, () => _evaluateAndPlay(entry));
  }

  /// Call right after a user-driven PageUp/PageDown changes
  /// [GeneratorPageController.position] (never for the auto-advance writes
  /// this controller makes itself — those already match what's playing).
  /// While paused, the page only moves the point a click resumes from.
  void onManualPageChange() {
    if (_duration == null || _pageCount == null) return;
    final generation = _generation;
    _pageTimer?.cancel();
    _pageTimer = Timer(_pageDebounce, () {
      if (generation != _generation) return;
      final page = _generatorPage?.position.value;
      if (page == null) return;
      if (state.value == PlaybackState.paused) {
        _cueAt(_secondsForPage(page));
      } else {
        _startPlaybackAt(page);
      }
    });
  }

  /// Pauses on lost focus or minimize. Focus coming back doesn't undo it —
  /// only [togglePause] does. When playback hasn't started yet (still in the
  /// dwell or loading), it starts out paused instead.
  void stopForLifecycle() {
    switch (state.value) {
      case PlaybackState.playing:
        _pause();
      case PlaybackState.paused:
        break;
      case PlaybackState.idle:
        if (_pendingEntry != null) _startPaused = true;
    }
  }

  bool get canToggle => state.value != PlaybackState.idle;

  void togglePause() {
    if (!canToggle) return;
    switch (state.value) {
      case PlaybackState.playing:
        _pause();
      case PlaybackState.paused:
        _resume();
      case PlaybackState.idle:
        break;
    }
  }

  /// Real path of the file currently shown in Quick Look, null when nothing
  /// is shown or a compare-diff is covering the preview.
  String? get shownPath => _pendingEntry?.realPath;

  /// Stops playback and releases the file — used when a file operation is
  /// about to move or delete it. Never restarts for the same file; [sync]
  /// only restarts it when the shown file changes.
  void stopShown() {
    final entry = _pendingEntry;
    if (entry == null) return;
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
    unawaited(_activePlayer.stop());
    state.dispose();
  }

  Future<void> _evaluateAndPlay(FileEntry entry) async {
    if (InAppVideoPlayer.canPreview(entry)) {
      final generation = _generation;
      final duration = await _video.durationOf(entry.realPath);
      if (duration == null || duration <= 0 || generation != _generation) {
        return;
      }
      _inAppVideo = true;
      _duration = duration;
      _pageCount = InAppVideoPlayer.pageCount;
      _playOrStartPaused();

      return;
    }
    _inAppVideo = false;
    if (PlayerRegistry.instance.config == null) return;
    final def = GeneratorRegistry.instance.forExtension(
      entry.extension,
      GeneratorUse.quickLook,
    );
    if (def == null || def.pagingMode != PagingMode.time) return;
    final generation = _generation;
    final hasAudio = await AudioStreamProbe.hasAudio(entry);
    if (!hasAudio || generation != _generation) return;
    final duration = await GeneratorRunner.probeDurationSeconds(entry);
    if (duration == null || duration <= 0 || generation != _generation) return;
    _duration = duration;
    _pageCount = def.pageCount;
    _playOrStartPaused();
  }

  void _playOrStartPaused() {
    final page = _generatorPage?.position.value ?? 0;
    if (_startPaused || !_resumed) {
      _startPaused = false;
      state.value = PlaybackState.paused;
      _cueAt(_secondsForPage(page));
      return;
    }
    _startPlaybackAt(page);
  }

  bool get _resumed {
    final state = WidgetsBinding.instance.lifecycleState;

    return state == null || state == AppLifecycleState.resumed;
  }

  double _secondsForPage(int page) {
    final duration = _duration;
    final pageCount = _pageCount;
    if (duration == null || pageCount == null) return 0;

    return startSecondsForPage(
      page: page,
      duration: duration,
      pageCount: pageCount,
    );
  }

  void _cueAt(double seconds) {
    _resumeAt = seconds;
    final entry = _pendingEntry;
    if (_inAppVideo && entry != null) {
      unawaited(_video.cue(entry.realPath, seconds));
    }
  }

  void _startPlaybackAt(int page) {
    if (_duration == null || _pageCount == null) return;
    _startPlaybackAtSeconds(_secondsForPage(page));
  }

  void _startPlaybackAtSeconds(double seconds) {
    final entry = _pendingEntry;
    if (_duration == null || entry == null) return;
    _beginClock(seconds);
    state.value = PlaybackState.playing;
    unawaited(_activePlayer.play(entry.realPath, seconds));
  }

  void _beginClock(double seconds) {
    _playStartSeconds = seconds;
    _stopwatch
      ..reset()
      ..start();
    _advanceTimer?.cancel();
    _advanceTimer = null;
    final pageCount = _pageCount;
    if (pageCount != null && pageCount > 1) {
      _advanceTimer = Timer.periodic(_advanceInterval, (_) => _advancePage());
    }
  }

  void _stopClock() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _stopwatch.stop();
  }

  double get _elapsed =>
      _playStartSeconds + _stopwatch.elapsed.inMilliseconds / 1000;

  void _pause() {
    final duration = _duration;
    if (duration == null) return;
    _pageTimer?.cancel();
    final elapsed = _elapsed;
    _stopClock();
    state.value = PlaybackState.paused;
    unawaited(_activePlayer.stop());
    _cueAt(elapsed >= duration ? 0 : elapsed);
  }

  void _resume() {
    if (_pendingEntry == null || _duration == null) return;
    _startPlaybackAtSeconds(_resumeAt);
  }

  void _advancePage() {
    final duration = _duration;
    final pageCount = _pageCount;
    final generatorPage = _generatorPage;
    if (duration == null || pageCount == null || generatorPage == null) return;
    final elapsed = _elapsed;
    if (elapsed >= duration) {
      _stopClock();
      generatorPage.position.value = pageCount - 1;
      state.value = PlaybackState.paused;
      _resumeAt = 0;

      return;
    }
    generatorPage.position.value = pageForElapsed(
      elapsedSeconds: elapsed,
      duration: duration,
      pageCount: pageCount,
    );
  }

  void _stopEverything() {
    _stopClock();
    final target = _activePlayer;
    _duration = null;
    _pageCount = null;
    _inAppVideo = false;
    _resumeAt = 0;
    state.value = PlaybackState.idle;
    unawaited(target.stop());
  }
}
