import 'package:path/path.dart' as p;

import '../../../core/platform/platform_paths.dart';
import 'quick_look_playback_controller.dart';

/// Tracks the live [QuickLookPlaybackController]s (Quick Look dialog, panel
/// and pop-out window each own one) so code outside the Quick Look widgets —
/// currently file operations — can stop playback and release the open file
/// before a task moves, deletes or replaces it.
class PlaybackRegistry {
  PlaybackRegistry._();

  static final PlaybackRegistry instance = PlaybackRegistry._();

  final Set<QuickLookPlaybackController> _controllers = {};

  void register(QuickLookPlaybackController controller) {
    _controllers.add(controller);
  }

  void unregister(QuickLookPlaybackController controller) {
    _controllers.remove(controller);
  }

  /// Stops playback on every controller whose shown file is one of [paths].
  void stopForPaths(Iterable<String> paths) {
    if (paths.isEmpty) return;
    final wanted = paths.map(_comparePath).toSet();
    for (final controller in _controllers) {
      final shown = controller.shownPath;
      if (shown == null || !wanted.contains(_comparePath(shown))) continue;
      controller.stopShown();
    }
  }

  static String _comparePath(String path) {
    final normalized = p.normalize(path);
    return PlatformPaths.isWindows ? normalized.toLowerCase() : normalized;
  }
}
