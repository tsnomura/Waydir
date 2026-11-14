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

  test(
    'focus loss stops and cues an in-app video, a click resumes it',
    () async {
      final video = _FakeVideo(100);
      final controller = QuickLookPlaybackController(video: video);
      final page = GeneratorPageController()
        ..pageCount = InAppVideoPlayer.pageCount;
      controller.sync(_clip, page, blocked: false);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(video.calls.last, 'play:/tmp/clip.mp4:0.0');

      controller.stopForLifecycle();
      controller.stopForLifecycle();
      expect(video.calls.where((c) => c == 'stop'), hasLength(1));
      expect(video.calls[video.calls.length - 2], 'stop');
      expect(video.calls.last, startsWith('cue:/tmp/clip.mp4:0.'));
      expect(controller.state.value, PlaybackState.paused);

      final cued = video.calls.last.substring('cue:'.length);
      controller.togglePause();
      expect(video.calls.last, 'play:$cued');
      expect(cued, isNot('/tmp/clip.mp4:0.0'));
      expect(controller.state.value, PlaybackState.playing);

      controller.dispose();
      await video.dispose();
      page.dispose();
    },
  );

  test('a click toggles a playing in-app video', () async {
    final video = _FakeVideo(100);
    final controller = QuickLookPlaybackController(video: video);
    final page = GeneratorPageController()
      ..pageCount = InAppVideoPlayer.pageCount;
    controller.sync(_clip, page, blocked: false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(controller.canToggle, isTrue);

    controller.togglePause();
    expect(controller.state.value, PlaybackState.paused);
    expect(video.calls.last, startsWith('cue:/tmp/clip.mp4:0.'));

    controller.togglePause();
    expect(controller.state.value, PlaybackState.playing);
    expect(video.calls.last, startsWith('play:/tmp/clip.mp4:0.'));

    controller.dispose();
    await video.dispose();
    page.dispose();
  });

  test('focus lost during the dwell starts out paused, unloaded', () async {
    final video = _FakeVideo(100);
    final controller = QuickLookPlaybackController(video: video);
    final page = GeneratorPageController()
      ..pageCount = InAppVideoPlayer.pageCount
      ..position.value = 3;
    controller.sync(_clip, page, blocked: false);
    controller.stopForLifecycle();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(video.calls.where((c) => c.startsWith('play')), isEmpty);
    expect(video.calls.last, 'cue:/tmp/clip.mp4:30.0');
    expect(controller.state.value, PlaybackState.paused);

    controller.togglePause();
    expect(video.calls.last, 'play:/tmp/clip.mp4:30.0');

    controller.dispose();
    await video.dispose();
    page.dispose();
  });

  test('paging while paused moves the resume point without playing', () async {
    final video = _FakeVideo(100);
    final controller = QuickLookPlaybackController(video: video);
    final page = GeneratorPageController()
      ..pageCount = InAppVideoPlayer.pageCount;
    page.onManualChange = controller.onManualPageChange;
    controller.sync(_clip, page, blocked: false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.stopForLifecycle();
    page.next();
    page.next();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(video.calls.last, 'cue:/tmp/clip.mp4:20.0');
    expect(video.calls.where((c) => c.startsWith('play')), hasLength(1));
    expect(controller.state.value, PlaybackState.paused);

    controller.togglePause();
    expect(video.calls.last, 'play:/tmp/clip.mp4:20.0');

    controller.dispose();
    await video.dispose();
    page.dispose();
  });

  test('a file-operation stop leaves nothing to toggle', () async {
    final video = _FakeVideo(100);
    final controller = QuickLookPlaybackController(video: video);
    final page = GeneratorPageController();
    controller.sync(_clip, page, blocked: false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.stopShown();
    controller.stopForLifecycle();
    controller.togglePause();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(video.calls.last, 'stop');
    expect(controller.state.value, PlaybackState.idle);

    controller.dispose();
    await video.dispose();
    page.dispose();
  });
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

final _clip = FileEntry.raw(
  name: 'clip.mp4',
  path: '/tmp/clip.mp4',
  type: FileItemType.file,
  size: 1,
  modifiedMs: 0,
);

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
  Future<void> cue(String path, double startSeconds) async {
    calls.add('cue:$path:$startSeconds');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}
