import 'dart:async';

import 'package:signals/signals.dart';

import '../../core/fs/waydir_core_loader.dart';
import '../../core/logging/app_logger.dart';

class FolderSizeScanner {
  final sizes = signal<Map<String, int>>({});
  final progress = signal<Map<String, int>>({});
  final computing = signal<Set<String>>({});

  static const _maxSessions = 4;

  final _sessions = <String, int>{};
  final _pending = <String>[];
  Timer? _timer;

  late final displaySizes = computed<Map<String, int>>(() {
    final done = sizes.value;
    final live = progress.value;
    if (live.isEmpty) return done;

    return {...done, ...live};
  });

  void scan(Iterable<String> paths) {
    final queued = <String>[
      for (final path in paths)
        if (!_sessions.containsKey(path) && !_pending.contains(path)) path,
    ];
    if (queued.isEmpty) return;
    _pending.addAll(queued);
    computing.value = {...computing.value, ...queued};
    _startPending();
    _ensureTimer();
  }

  void _startPending() {
    final started = <String>[];
    final failed = <String>[];
    while (_pending.isNotEmpty && _sessions.length < _maxSessions) {
      final path = _pending.removeAt(0);
      int? session;
      try {
        session = WaydirCoreLoader.folderScanStart(path);
      } catch (e, st) {
        log.warn(
          'navigation',
          'folder size scan start failed',
          error: e,
          stack: st,
        );
        session = null;
      }
      if (session == null) {
        failed.add(path);
        continue;
      }
      _sessions[path] = session;
      started.add(path);
    }
    if (failed.isNotEmpty) {
      computing.value = computing.value.difference(failed.toSet());
    }
    if (started.isNotEmpty) {
      progress.value = {...progress.value, for (final path in started) path: 0};
    }
  }

  void _ensureTimer() {
    if (_sessions.isEmpty) {
      _timer?.cancel();
      _timer = null;

      return;
    }
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _poll(),
    );
  }

  void _poll() {
    final progressNext = Map<String, int>.from(progress.value);
    final sizesNext = Map<String, int>.from(sizes.value);
    final computingNext = Set<String>.from(computing.value);
    final finished = <String>[];
    _sessions.forEach((path, session) {
      try {
        final r = WaydirCoreLoader.folderScanPoll(session);
        if (r.done) {
          sizesNext[path] = r.bytes;
          progressNext.remove(path);
          computingNext.remove(path);
          finished.add(path);
        } else {
          progressNext[path] = r.bytes;
        }
      } catch (e, st) {
        log.warn(
          'navigation',
          'folder size scan poll failed',
          error: e,
          stack: st,
        );
        progressNext.remove(path);
        computingNext.remove(path);
        finished.add(path);
      }
    });
    for (final path in finished) {
      final session = _sessions.remove(path);
      if (session == null) continue;
      try {
        WaydirCoreLoader.folderScanFree(session);
      } catch (e, st) {
        log.warn(
          'navigation',
          'folder size scan free failed',
          error: e,
          stack: st,
        );
      }
    }
    batch(() {
      progress.value = progressNext;
      sizes.value = sizesNext;
      computing.value = computingNext;
    });
    _startPending();
    _ensureTimer();
  }

  void cancelAll() {
    _timer?.cancel();
    _timer = null;
    for (final session in _sessions.values) {
      try {
        WaydirCoreLoader.folderScanCancel(session);
        WaydirCoreLoader.folderScanFree(session);
      } catch (e, st) {
        log.warn(
          'navigation',
          'folder size scan cancel failed',
          error: e,
          stack: st,
        );
      }
    }
    _sessions.clear();
    _pending.clear();
    if (sizes.value.isEmpty &&
        progress.value.isEmpty &&
        computing.value.isEmpty) {
      return;
    }
    batch(() {
      sizes.value = {};
      progress.value = {};
      computing.value = {};
    });
  }

  void dispose() => cancelAll();
}
