@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_page_controller.dart';
import 'package:waydir/features/quick_look/generators/generator_preview.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';
import 'package:waydir/ui/theme/app_theme.dart';

void main() {
  late Directory tmp;
  late GeneratorPageController page;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('waydir_ql_frame_swap_');
    page = GeneratorPageController();
    GeneratorRegistry.instance.clearForTesting();
    GeneratorRegistry.instance.registerForTesting(_def());
  });

  tearDown(() {
    page.dispose();
    GeneratorRegistry.instance.clearForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('paging holds the previous frame until the next one is ready, '
      'then swaps without a blank', (tester) async {
    final video = File(p.join(tmp.path, 'video.mp4'))
      ..writeAsBytesSync(_onePixelPng);
    final entry = FileEntry.fromFileSystemEntity(video);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(),
          home: Scaffold(
            body: GeneratorPreview(
              entry: entry,
              page: page,
              editorActive: signal(false),
            ),
          ),
        ),
      );

      final first = await _waitForFrame(tester);
      expect(first, isNotNull, reason: 'page 0 frame should appear');

      page.position.value = 1;
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      expect(
        _framePath(tester),
        first,
        reason:
            'the previous frame must stay visible while the next one '
            'is still generating (no blank between pages)',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final next = await _waitForFrame(tester, otherThan: first);
      expect(next, isNotNull, reason: 'page 1 frame should appear');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_framePath(tester), next);
    });
  });
}

// Page 1 takes 0.7s to generate so the hold window is wide enough to assert
// on deterministically; the pages only differ in their cache path, which is
// what the assertions key off of.
GeneratorDef _def() => GeneratorDef(
  id: 'test-frame-swap',
  extensions: {'mp4'},
  cmd: 'sh',
  args: [
    '-c',
    'if [ "%POSITION%" = "1" ]; then sleep 0.7; fi; '
        'cp "%INPUT%" "%OUTPUT%"',
  ],
  timeout: const Duration(seconds: 15),
  outputExt: 'png',
  pagingMode: PagingMode.time,
  pageCount: 3,
  probeCmd: 'sh',
  probeArgs: ['-c', 'echo 10'],
);

Future<String?> _waitForFrame(WidgetTester tester, {String? otherThan}) async {
  for (var i = 0; i < 200; i++) {
    final path = _framePath(tester, otherThan: otherThan);
    if (path != null) return path;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }

  return null;
}

String? _framePath(WidgetTester tester, {String? otherThan}) {
  for (final element in find.byType(Image).evaluate()) {
    final widget = element.widget as Image;
    final provider = widget.image;
    if (provider is FileImage && provider.file.path != otherThan) {
      return provider.file.path;
    }
  }

  return null;
}

final List<int> _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
