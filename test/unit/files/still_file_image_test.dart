import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/files/still_file_image.dart';

final _animatedGif = base64Decode(
  'R0lGODlhBAACAIEAAP8AAAD/AAAA/wAAACH5BAACAAAAIf8LTkVUU0NBUEUyLjAD'
  'AQAAACwAAAAABAACAAAIBwABCBwoMCAAIfkEAAIAAAAh/wtORVRTQ0FQRTIuMAMB'
  'AAAALAAAAAAEAAIAAAgHAAMIHCgwIAAh+QQAAgAAACH/C05FVFNDQVBFMi4wAwEA'
  'AAAsAAAAAAQAAgAACAcABQgcKDAgADs=',
);

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGP8z4AATEhsBgAZNQEDGy9LEgAAAABJRU5ErkJggg==',
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('still_file_image_test');
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    await dir.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);

    return file;
  }

  Future<(ImageStream, ImageInfo)> resolve(ImageProvider provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final done = Completer<ImageInfo>();
    stream.addListener(
      ImageStreamListener(
        (info, _) {
          if (!done.isCompleted) done.complete(info);
        },
        onError: (error, _) {
          if (!done.isCompleted) done.completeError(error);
        },
      ),
    );

    return (stream, await done.future);
  }

  testWidgets('animated gif resolves to a single still frame', (tester) async {
    await tester.runAsync(() async {
      final file = await writeFile('anim.gif', _animatedGif);

      final (still, info) = await resolve(StillFileImage(file, maxWidth: 100));
      expect(still.completer, isA<OneFrameImageStreamCompleter>());
      expect(info.image.width, 4);
      expect(info.image.height, 2);
    });
  });

  testWidgets('downscales to maxWidth keeping the aspect ratio', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final file = await writeFile('still.png', _png);

      final (_, info) = await resolve(StillFileImage(file, maxWidth: 2));
      expect(info.image.width, 2);
      expect(info.image.height, 1);
    });
  });

  testWidgets('an empty file reports an error', (tester) async {
    await tester.runAsync(() async {
      final file = await writeFile('empty.gif', const <int>[]);

      await expectLater(
        resolve(StillFileImage(file, maxWidth: 100)),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('thumbnailImage animates unless asked for a still', () {
    final file = File('/x/a.gif');
    expect(
      thumbnailImage(file, maxWidth: 100, still: true),
      StillFileImage(file, maxWidth: 100),
    );
    expect(
      thumbnailImage(file, maxWidth: 100, still: false),
      ResizeImage(FileImage(file), width: 100),
    );
  });

  test('equality depends on path and maxWidth', () {
    final a = StillFileImage(File('/x/a.gif'), maxWidth: 100);
    expect(a, StillFileImage(File('/x/a.gif'), maxWidth: 100));
    expect(a, isNot(StillFileImage(File('/x/a.gif'), maxWidth: 200)));
    expect(a, isNot(StillFileImage(File('/x/b.gif'), maxWidth: 100)));
  });
}
