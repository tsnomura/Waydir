import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';

import '../../../core/platform/platform_paths.dart';
import '../../../core/settings/settings_store.dart';
import 'quick_look_playback_controller.dart';

/// Tracks the live [QuickLookPlaybackController]s (Quick Look dialog, panel
/// and pop-out window each own one) so code outside the Quick Look widgets —
/// file operations, the global mute setting — can reach every one of them.
class PlaybackRegistry {
  PlaybackRegistry._();

  static final PlaybackRegistry instance = PlaybackRegistry._();

  final Set<QuickLookPlaybackController> _controllers = {};
  void Function()? _muteSub;

  void register(QuickLookPlaybackController controller) {
    _controllers.add(controller);
    _muteSub ??= effect(() {
      final muted = SettingsStore.instance.quickLookMuteAudio.value;
      untracked(() {
        for (final c in _controllers) {
          c.setMuted(muted);
        }
      });
    });
    controller.setMuted(SettingsStore.instance.quickLookMuteAudio.peek());
  }

  void unregister(QuickLookPlaybackController controller) {
    _controllers.remove(controller);
  }

  /// Stops playback on every controller whose shown file is one of [paths].
  Future<void> stopForPaths(Iterable<String> paths) {
    if (paths.isEmpty) return Future.value();
    final wanted = paths.map(_comparePath).toSet();
    final stopping = <Future<void>>[];
    for (final controller in _controllers) {
      final shown = controller.shownPath;
      if (shown == null || !wanted.contains(_comparePath(shown))) continue;
      stopping.add(controller.stopShown());
    }

    return Future.wait(stopping);
  }

  static String _comparePath(String path) {
    final normalized = p.normalize(path);
    return PlatformPaths.isWindows ? normalized.toLowerCase() : normalized;
  }
}
