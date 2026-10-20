import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signals/signals.dart';
import '../../core/logging/app_logger.dart';
import 'drive_model.dart';
import 'drive_service.dart';

class DriveStore {
  final drives = signal<List<Drive>>([]);
  final DriveService _service;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _refreshAgain = false;

  DriveStore({DriveService? service}) : _service = service ?? DriveService() {
    _init();
  }

  @visibleForTesting
  Future<void> refresh() => _refresh();

  void _init() {
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refresh();
    });
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
      drives.value = updatedDrives;
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
    _timer?.cancel();
  }
}

final driveStore = DriveStore();
