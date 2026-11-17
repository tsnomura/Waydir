import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Indeterminate progress ring. Under reduce motion it advances in a few
/// steps per second instead of repainting on every frame, so a long-running
/// spinner doesn't keep a remote display busy.
class AppSpinner extends StatelessWidget {
  final double strokeWidth;
  final Color? color;

  const AppSpinner({super.key, this.strokeWidth = 2, this.color});

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) {
      return _SteppedSpinner(strokeWidth: strokeWidth, color: color);
    }

    return CircularProgressIndicator(strokeWidth: strokeWidth, color: color);
  }
}

class _SteppedSpinner extends StatefulWidget {
  final double strokeWidth;
  final Color? color;

  const _SteppedSpinner({required this.strokeWidth, this.color});

  @override
  State<_SteppedSpinner> createState() => _SteppedSpinnerState();
}

class _SteppedSpinnerState extends State<_SteppedSpinner> {
  static const _steps = 8;
  static const _interval = Duration(milliseconds: 250);

  Timer? _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (mounted) setState(() => _step = (_step + 1) % _steps);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Transform.rotate(
        angle: 2 * math.pi * _step / _steps,
        child: CircularProgressIndicator(
          value: 0.3,
          strokeWidth: widget.strokeWidth,
          color: widget.color,
        ),
      ),
    );
  }
}
