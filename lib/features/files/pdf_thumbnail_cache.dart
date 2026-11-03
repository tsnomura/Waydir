import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/fs/waydir_core_loader.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/app_dirs.dart';
import '../../core/platform/platform_paths.dart';
import '../../utils/concurrency_gate.dart';
import 'remote_thumbnail_cache.dart';

const _renderWidth = 360;

class PdfThumbnailCache {
  PdfThumbnailCache._();

  static final _gate = ConcurrencyGate(2);
  static final _inFlight = <String, Future<String?>>{};
  static final _failedKeys = <String>{};

  static Future<String?> thumbnail(FileEntry entry) {
    final key = sha256
        .convert(
          utf8.encode(
            'pdf|${entry.realPath}|${entry.modifiedMs}|${entry.size}|$_renderWidth',
          ),
        )
        .toString();
    if (_failedKeys.contains(key)) return Future.value(null);

    return _inFlight.putIfAbsent(key, () async {
      try {
        final path = await _build(entry, key);
        if (path == null) _failedKeys.add(key);

        return path;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static Future<String?> _build(FileEntry entry, String key) async {
    final dir = await AppDirs.generatorCache();
    final target = p.join(dir, 'pdf-$key.png');
    if (await File(target).exists()) return target;

    final source = PlatformPaths.isRemoteUri(entry.realPath)
        ? await RemoteThumbnailCache.fetch(entry)
        : entry.realPath;
    if (source == null) return null;

    final tmp = p.join(dir, 'tmp-pdf-$key.png');
    await _gate.acquire();
    try {
      final page = await _renderInIsolate(source);
      if (page == null) return null;
      final png = await _encodePng(page);
      if (png == null) return null;
      await File(tmp).writeAsBytes(png, flush: true);
      await File(tmp).rename(target);

      return target;
    } catch (error, stack) {
      log.warn(
        'thumbnails',
        'pdf thumbnail failed for ${entry.realPath}',
        error: error,
        stack: stack,
      );
      try {
        await File(tmp).delete();
      } catch (_) {}

      return null;
    } finally {
      _gate.release();
    }
  }

  static Future<List<int>?> _encodePng(PdfRenderedPage page) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(page.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: page.width,
      height: page.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);

      return data?.buffer.asUint8List();
    } finally {
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}

Future<PdfRenderedPage?> _renderInIsolate(String path) =>
    Isolate.run(() => WaydirCoreLoader.pdfRenderPage(path, 0, _renderWidth));
