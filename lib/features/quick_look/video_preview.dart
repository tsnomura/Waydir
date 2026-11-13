import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/strings.g.dart';
import '../../ui/icons/waydir_icons.dart';
import '../../ui/theme/app_theme.dart';
import 'generators/generator_page_controller.dart';
import 'generators/generator_preview.dart';
import 'player/in_app_video.dart';
import 'quick_look_common.dart';

/// The in-app picture for a local video: the [VideoPlayer] texture owned by
/// [InAppVideoPlayer], with the same time-page bar the thumbnail previews
/// use. Every playback decision (when to start, stop, or seek) is made by
/// the Quick Look playback controller; this widget only mirrors what it
/// loaded.
class VideoPreview extends StatefulWidget {
  final InAppVideoPlayer video;
  final String path;
  final GeneratorPageController page;

  const VideoPreview({
    super.key,
    required this.video,
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
        final controller = widget.video.controller;

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
              else if (widget.video.failed.value)
                Positioned.fill(
                  child: QlCentered(
                    icon: WaydirIconsRegular.file,
                    message: t.quickLook.videoLoadFailed,
                  ),
                )
              else
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
