import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/strings.g.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/theme/app_theme.dart';
import 'generators/generator_page_controller.dart';
import 'generators/generator_preview.dart';
import 'player/in_app_video.dart';
import 'player/quick_look_playback_controller.dart';
import 'quick_look_common.dart';

/// The in-app picture for a local video: the [VideoPlayer] texture owned by
/// [InAppVideoPlayer], with the same time-page bar the thumbnail previews
/// use. Every playback decision (when to start, stop, or seek) is made by
/// the Quick Look playback controller; this widget only mirrors what it
/// loaded.
class VideoPreview extends StatefulWidget {
  final QuickLookPlaybackController playback;
  final String path;
  final GeneratorPageController page;

  const VideoPreview({
    super.key,
    required this.playback,
    required this.path,
    required this.page,
  });

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  @override
  Widget build(BuildContext context) {
    widget.page.pageCount = InAppVideoPlayer.pageCount;

    return SignalBuilder(
      builder: (context) {
        final video = widget.playback.video;
        final controller = video.current.value;
        final paused = widget.playback.state.value == PlaybackState.paused;

        return Container(
          color: AppColors.bg,
          alignment: Alignment.center,
          child: Stack(
            children: [
              if (controller != null && controller.value.isInitialized)
                Positioned.fill(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                )
              else if (video.failed.value)
                Positioned.fill(
                  child: QlCentered(
                    icon: WaydirIconsRegular.file,
                    message: t.quickLook.videoLoadFailed,
                  ),
                )
              else if (!paused)
                const Positioned.fill(child: QlCentered.spinner()),
              if (InAppVideoPlayer.pageCount > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: GeneratorPageBar(
                    page: widget.page,
                    pageCount: InAppVideoPlayer.pageCount,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Wraps a playable preview (the in-app video, or the generator frames an
/// external audio player plays alongside) so a click toggles pause, and
/// shows a pause badge while paused. Inert while nothing is playing.
class PlaybackSurface extends StatelessWidget {
  final QuickLookPlaybackController playback;
  final Widget child;

  const PlaybackSurface({
    super.key,
    required this.playback,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final state = playback.state.value;
      final active = playback.canToggle;

      return MouseRegion(
        cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? playback.togglePause : null,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              if (state == PlaybackState.paused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface.withValues(alpha: 0.8),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Icon(
                          WaydirIconsRegular.pause,
                          size: 32,
                          color: AppColors.fgMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
