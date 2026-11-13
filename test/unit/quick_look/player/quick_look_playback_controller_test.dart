import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/generators/generator_def.dart';
import 'package:waydir/features/quick_look/generators/generator_page_controller.dart';
import 'package:waydir/features/quick_look/generators/generator_registry.dart';
import 'package:waydir/features/quick_look/player/in_app_video.dart';
import 'package:waydir/features/quick_look/player/quick_look_playback_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'in-app video plays after the dwell and re-seeks on page moves',
    () async {
      final video = _FakeVideo(100);
      final controller = QuickLookPlaybackController(video: video);
      final page = GeneratorPageController();
      page.onManualChange = controller.onManualPageChange;
      final entry = FileEntry.raw(
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
        type: FileItemType.file,
        size: 1,
        modifiedMs: 0,
      );

      controller.sync(entry, page, blocked: false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(video.calls, contains('play:/tmp/clip.mp4:0.0'));

      page.pageCount = InAppVideoPlayer.pageCount;
      for (var i = 0; i < 4; i++) {
        page.next();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(video.calls.last, 'play:/tmp/clip.mp4:40.0');

      controller.sync(null, page, blocked: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(video.calls.last, 'stop');

      controller.dispose();
      await video.dispose();
      page.dispose();
    },
  );

  test('a configured generator keeps winning over the in-app preview', () {
    GeneratorRegistry.instance.registerForTesting(
      GeneratorDef(
        id: 'video-thumbnail',
        extensions: {'mp4'},
        cmd: 'ffmpeg',
        args: const [],
        timeout: const Duration(seconds: 8),
        outputExt: 'png',
      ),
    );
    final entry = FileEntry.raw(
      name: 'clip.mp4',
      path: '/tmp/clip.mp4',
      type: FileItemType.file,
      size: 1,
      modifiedMs: 0,
    );

    expect(InAppVideoPlayer.canPreview(entry), isFalse);
    GeneratorRegistry.instance.clearForTesting();
  });
}

class _FakeVideo extends InAppVideoPlayer {
  _FakeVideo(this.duration);

  final double? duration;
  final calls = <String>[];

  @override
  Future<double?> durationOf(String path) async {
    calls.add('duration:$path');
    return duration;
  }

  @override
  Future<void> play(String path, double startSeconds) async {
    calls.add('play:$path:$startSeconds');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}
