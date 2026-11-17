import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/app_activity.dart';
import 'drive_model.dart';
import 'drive_service.dart';

class DriveStore {
  final drives = signal<List<Drive>>([]);
  final DriveService _service;
  late final _poller = ActivityPoller(
    interval: const Duration(seconds: 3),
    onPoll: _refresh,
  );
  Future<void>? _inFlight;
  bool _refreshAgain = false;

  DriveStore({DriveService? service}) : _service = service ?? DriveService() {
    _init();
  }

  @visibleForTesting
  Future<void> refresh() => _refresh();

  void _init() {
    _refresh();
    _poller.start();
  }

  Future<void> _refresh() {
    final running = _inFlight;
    if (running != null) {
      _refreshAgain = true;

      return running;
    }
    final next = _load().whenComplete(() {
      _inFlight = null;
      if (_refreshAgain) {
        _refreshAgain = false;
        _refresh();
      }
    });
    _inFlight = next;

    return next;
  }

  Future<void> _load() async {
    try {
      final updatedDrives = await _service.getDrives();
      if (!sameDrivesForDisplay(drives.value, updatedDrives)) {
        drives.value = updatedDrives;
      }
    } catch (e, st) {
      log.warn('drives', 'drive refresh failed', error: e, stack: st);
    }
  }

  Future<void> mount(Drive drive) async {
    await _service.mount(drive);
    await _refresh();
  }

  Future<void> mountWithPassword(Drive drive, String password) async {
    await _service.mountWithPassword(drive, password);
    await _refresh();
  }

  Future<void> unmount(Drive drive) async {
    try {
      await _service.unmount(drive);
      await _refresh();
    } catch (e, st) {
      log.warn('drives', 'drive unmount failed', error: e, stack: st);
    }
  }

  void dispose() {
    _poller.dispose();
  }
}

final driveStore = DriveStore();

const _spaceChangeFraction = 1000;

@visibleForTesting
bool sameDrivesForDisplay(List<Drive> shown, List<Drive> probed) {
  if (shown.length != probed.length) return false;
  for (var i = 0; i < shown.length; i++) {
    final a = shown[i];
    final b = probed[i];
    if (a.id != b.id ||
        a.label != b.label ||
        a.mountPoint != b.mountPoint ||
        a.isRemovable != b.isRemovable ||
        a.isNetwork != b.isNetwork ||
        a.remoteTarget != b.remoteTarget ||
        a.fsType != b.fsType ||
        !_sameSpaceForDisplay(a.space, b.space)) {
      return false;
    }
  }

  return true;
}

bool _sameSpaceForDisplay(DriveSpace? a, DriveSpace? b) {
  if (a == null || b == null) return a == b;
  if (a.totalBytes != b.totalBytes) return false;

  return (a.freeBytes - b.freeBytes).abs() * _spaceChangeFraction <
      a.totalBytes;
}
