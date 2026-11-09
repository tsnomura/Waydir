import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

@immutable
class StillFileImage extends ImageProvider<StillFileImage> {
  final File file;
  final int maxWidth;

  const StillFileImage(this.file, {required this.maxWidth});

  @override
  Future<StillFileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<StillFileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    StillFileImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    _loadFirstFrame(key, decode),
    informationCollector: () => <DiagnosticsNode>[
      ErrorDescription('Path: ${file.path}'),
    ],
  );

  Future<ImageInfo> _loadFirstFrame(
    StillFileImage key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key.file.readAsBytes();
    if (bytes.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('${key.file.path} is empty and cannot be loaded.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(
      buffer,
      getTargetSize: (width, height) => width > key.maxWidth
          ? ui.TargetImageSize(width: key.maxWidth)
          : const ui.TargetImageSize(),
    );
    try {
      final frame = await codec.getNextFrame();

      return ImageInfo(image: frame.image);
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StillFileImage &&
      other.file.path == file.path &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(file.path, maxWidth);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'StillFileImage')}("${file.path}", maxWidth: $maxWidth)';
}

ImageProvider thumbnailImage(
  File file, {
  required int maxWidth,
  required bool still,
}) => still
    ? StillFileImage(file, maxWidth: maxWidth)
    : ResizeImage.resizeIfNeeded(maxWidth, null, FileImage(file));
