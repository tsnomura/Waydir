part of '../file_view.dart';

class _PinnedVerticalScrollbar extends StatelessWidget {
  final ScrollController controller;
  final List<double> marks;
  const _PinnedVerticalScrollbar({
    required this.controller,
    this.marks = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;

        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (!controller.hasClients) return const SizedBox.shrink();
            final position = controller.position;
            if (!position.hasContentDimensions ||
                !position.hasViewportDimension ||
                !position.hasPixels) {
              return const SizedBox.shrink();
            }
            final maxScroll = position.maxScrollExtent;
            final viewport = position.viewportDimension;
            if (maxScroll <= 0 || viewport <= 0) {
              return const SizedBox.shrink();
            }
            final thumbHeight = math.max(
              24.0,
              trackHeight * viewport / (viewport + maxScroll),
            );
            final maxTravel = trackHeight - thumbHeight;
            final t = (position.pixels / maxScroll).clamp(0.0, 1.0);
            final top = maxTravel * t;

            return Stack(
              children: [
                if (marks.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _ScrollbarMarksPainter(
                            marks: marks,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: top,
                  right: 0,
                  width: _kScrollbarThumbWidth,
                  height: thumbHeight,
                  child: GestureDetector(
                    onVerticalDragUpdate: (d) {
                      if (maxTravel <= 0) return;
                      final delta = d.delta.dy / maxTravel * maxScroll;
                      controller.jumpTo(
                        (position.pixels + delta).clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        ),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.fgSubtle.withValues(
                          alpha: marks.isEmpty ? 1 : 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ScrollbarMarksPainter extends CustomPainter {
  final List<double> marks;
  final Color color;

  const _ScrollbarMarksPainter({required this.marks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const tick = 2.0;
    var runTop = -1.0;
    var runBottom = -1.0;
    for (final f in marks) {
      final y = (f * size.height - tick / 2).clamp(0.0, size.height - tick);
      if (runTop >= 0 && y <= runBottom) {
        runBottom = math.max(runBottom, y + tick);
        continue;
      }
      if (runTop >= 0) {
        canvas.drawRect(Rect.fromLTRB(0, runTop, size.width, runBottom), paint);
      }
      runTop = y;
      runBottom = y + tick;
    }
    if (runTop >= 0) {
      canvas.drawRect(Rect.fromLTRB(0, runTop, size.width, runBottom), paint);
    }
  }

  @override
  bool shouldRepaint(_ScrollbarMarksPainter old) =>
      old.color != color || !listEquals(old.marks, marks);
}
