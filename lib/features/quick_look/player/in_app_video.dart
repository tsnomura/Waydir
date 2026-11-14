import 'dart:async';
import 'dart:io';

import 'package:signals/signals.dart';
import 'package:video_player/video_player.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/platform/platform_paths.dart';
import '../generators/generator_def.dart';
import '../generators/generator_registry.dart';
import '../media_info.dart';
import 'quick_look_player.dart';

/// Quick Look's in-app [QuickLookPlayer]: plays local video files on a
/// [VideoPlayerController] (fvp, an FFmpeg-backed engine on desktop) so
/// picture and sound come from the same engine, instead of an external
/// command drawing the sound while a generator draws the picture.
///
/// Only takes over files the generator path wouldn't handle: a configured
/// generator for the extension still wins (an explicit user choice), and
/// remote (`sftp://`/`smb://`) files have no local path for the decoder to
/// open, so they keep the existing fallback.
class InAppVideoPlayer implements QuickLookPlayer {
  /// How many time pages a video is split into in Quick Look — the same 10
  /// evenly-spaced frames the video-thumbnail generator uses, so
  /// PageUp/PageDown feels the same in both preview styles.
  static const pageCount = 10;

  String? _path;
  VideoPlayerController? _controller;
  bool _disposed = false;
  int _epoch = 0;
  Future<void> _tail = Future.value();

  /// What, if anything, is currently loaded — the preview widget renders its
  /// [VideoPlayer] off this.
  final current = signal<VideoPlayerController?>(null);

  /// True when the last load failed (unopenable file, unsupported codec) —
  /// the preview shows its no-preview message instead of spinning.
  final failed = signal(false);

  static bool canPreview(FileEntry entry) {
    if (!mediaVideoExts.contains(entry.extension)) return false;
    if (PlatformPaths.isRemoteUri(entry.realPath)) return false;
    final def = GeneratorRegistry.instance.forExtension(
      entry.extension,
      GeneratorUse.quickLook,
    );

    return def == null;
  }

  /// Duration of [path] in seconds — null when the file can't be opened,
  /// the way an ffprobe failure reads as "not playable" for audio.
  Future<double?> durationOf(String path) async {
    final controller = _path == path ? _controller : await _load(path);
    if (controller == null) return null;

    return controller.value.duration.inMilliseconds / 1000;
  }

  @override
  Future<void> play(String path, double startSeconds) async {
    final controller = _path == path ? _controller : await _load(path);
    if (controller == null) return;
    if (startSeconds > 0 || controller.value.position > Duration.zero) {
      await controller.seekTo(_at(startSeconds));
    }
    await controller.play();
  }

  /// Shows the frame at [startSeconds] without playing: a fresh load plus a
  /// seek, never a pause of a playing engine. Dropped when [stop] runs
  /// before the load lands.
  Future<void> cue(String path, double startSeconds) async {
    final epoch = _epoch;
    final controller = _path == path ? _controller : await _load(path);
    if (controller == null || epoch != _epoch) return;
    await controller.seekTo(_at(startSeconds));
  }

  static Duration _at(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  /// Drops the preview immediately, but lets the engine's [VideoPlayer]
  /// texture unmount first and disposes the controller a beat later.
  /// Disposing synchronously deregisters the engine texture while the
  /// widget is still on screen, so the raster thread keeps drawing a
  /// dead texture (engine warnings plus a software-GL render spin) until
  /// the rebuild lands.
  @override
  Future<void> stop() async {
    _epoch++;
    _release();
  }

  void _release() {
    final controller = _controller;
    _controller = null;
    _path = null;
    current.value = null;
    if (controller == null) return;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 1), () async {
        try {
          await controller.dispose();
        } catch (error, stack) {
          log.warn(
            'quick-look',
            'in-app video dispose failed',
            error: error,
            stack: stack,
          );
        }
      }),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    current.dispose();
    failed.dispose();
  }

  Future<VideoPlayerController?> _load(String path) {
    final epoch = _epoch;
    final future = _tail.then((_) => _loadNow(path, epoch));
    _tail = future.then((_) {}, onError: (Object _) {});

    return future;
  }

  Future<VideoPlayerController?> _loadNow(String path, int epoch) async {
    if (_disposed || epoch != _epoch) return null;
    if (_path == path && _controller != null) return _controller;
    try {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      if (_disposed || epoch != _epoch) {
        await controller.dispose();

        return null;
      }
      _release();
      _path = path;
      _controller = controller;
      failed.value = false;
      current.value = controller;

      return controller;
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'in-app video failed to load $path',
        error: error,
        stack: stack,
      );
      if (epoch == _epoch) failed.value = true;

      return null;
    }
  }
}
