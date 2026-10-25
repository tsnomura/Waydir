import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/core/platform/platform_paths.dart';
import 'package:waydir/features/quick_look/generators/generator_page_controller.dart';
import 'package:waydir/features/quick_look/player/playback_registry.dart';
import 'package:waydir/features/quick_look/player/quick_look_playback_controller.dart';
import 'package:waydir/features/quick_look/player/quick_look_player.dart';

class _RecordingPlayer implements QuickLookPlayer {
  final played = <String>[];
  var stopCount = 0;

  @override
  Future<void> play(String path, double startSeconds) async {
    played.add(path);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

FileEntry _entry(String path) => FileEntry(
  name: p.basename(path),
  path: path,
  type: FileItemType.file,
  size: 1,
  modified: DateTime(2026),
);

void main() {
  late _RecordingPlayer player;
  late GeneratorPageController page;
  late QuickLookPlaybackController controller;

  setUp(() {
    player = _RecordingPlayer();
    page = GeneratorPageController();
    controller = QuickLookPlaybackController(player: player);
    PlaybackRegistry.instance.register(controller);
  });

  tearDown(() {
    PlaybackRegistry.instance.unregister(controller);
    controller.dispose();
    page.dispose();
    PlatformPaths.isWindowsOverrideForTesting = null;
  });

  group('PlaybackRegistry.stopForPaths', () {
    test('stops the controller showing a listed file', () {
      controller.sync(_entry('/data/song.mp3'), page, blocked: false);
      final baseline = player.stopCount;

      PlaybackRegistry.instance.stopForPaths(['/data/song.mp3']);

      expect(player.stopCount, baseline + 1);
    });

    test('leaves controllers showing other files alone', () {
      controller.sync(_entry('/data/song.mp3'), page, blocked: false);
      final baseline = player.stopCount;

      PlaybackRegistry.instance.stopForPaths(['/data/other.mp3']);

      expect(player.stopCount, baseline);
    });

    test('is a no-op for an empty path list', () {
      controller.sync(_entry('/data/song.mp3'), page, blocked: false);
      final baseline = player.stopCount;

      PlaybackRegistry.instance.stopForPaths(const []);

      expect(player.stopCount, baseline);
    });

    test('does not stop while a compare diff covers the preview', () {
      controller.sync(_entry('/data/song.mp3'), page, blocked: true);
      final baseline = player.stopCount;

      PlaybackRegistry.instance.stopForPaths(['/data/song.mp3']);

      expect(player.stopCount, baseline);
    });

    test('matches paths case-insensitively on Windows', () {
      PlatformPaths.isWindowsOverrideForTesting = true;
      controller.sync(_entry(r'C:\Music\SONG.mp3'), page, blocked: false);
      final baseline = player.stopCount;

      PlaybackRegistry.instance.stopForPaths([r'c:\music\song.mp3']);

      expect(player.stopCount, baseline + 1);
    });

    test('only stops registered controllers', () {
      final otherPlayer = _RecordingPlayer();
      final other = QuickLookPlaybackController(player: otherPlayer);
      PlaybackRegistry.instance.register(other);
      controller.sync(_entry('/data/song.mp3'), page, blocked: false);
      other.sync(_entry('/data/song.mp3'), page, blocked: false);
      final baseline = player.stopCount;
      final otherBaseline = otherPlayer.stopCount;

      PlaybackRegistry.instance.unregister(other);
      PlaybackRegistry.instance.stopForPaths(['/data/song.mp3']);

      expect(player.stopCount, baseline + 1);
      expect(otherPlayer.stopCount, otherBaseline);
      other.dispose();
    });

    test('stops every controller showing a listed file', () {
      final otherPlayer = _RecordingPlayer();
      final other = QuickLookPlaybackController(player: otherPlayer);
      PlaybackRegistry.instance.register(other);
      controller.sync(_entry('/data/a.mp3'), page, blocked: false);
      other.sync(_entry('/data/b.mp3'), page, blocked: false);
      final baseline = player.stopCount;
      final otherBaseline = otherPlayer.stopCount;

      PlaybackRegistry.instance.stopForPaths(['/data/a.mp3', '/data/b.mp3']);

      expect(player.stopCount, baseline + 1);
      expect(otherPlayer.stopCount, otherBaseline + 1);
      other.dispose();
    });
  });
}
