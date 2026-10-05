import 'package:flutter/material.dart';

import '../../ui/theme/app_text_styles.dart';

class StatusChip extends StatelessWidget {
  final String glyph;
  final Color color;
  final double size;

  const StatusChip({
    super.key,
    required this.glyph,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: color,
      child: Text(
        glyph,
        maxLines: 1,
        style: context.txt.bodyEmphasis.copyWith(
          color: onColor,
          fontSize: size * 0.72,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
