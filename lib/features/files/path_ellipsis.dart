import 'package:flutter/material.dart';

const kEllipsis = '…';

typedef TextFits = bool Function(String text);

String ellipsizePathStart(
  String path,
  TextFits fits, {
  String separator = '/',
}) {
  if (path.isEmpty || fits(path)) return path;

  final parts = path.split(separator);
  for (var i = 1; i < parts.length; i++) {
    final candidate = '$kEllipsis$separator${parts.sublist(i).join(separator)}';
    if (fits(candidate)) return candidate;
  }

  final last = parts.last;
  var lo = 0;
  var hi = last.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (fits('$kEllipsis${last.substring(mid)}')) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }

  return '$kEllipsis${last.substring(lo)}';
}

String ellipsizeMiddle(String text, TextFits fits, {int keepTail = 0}) {
  if (text.isEmpty || fits(text)) return text;

  final tailLen = keepTail.clamp(0, text.length);
  final tail = text.substring(text.length - tailLen);
  var lo = 0;
  var hi = text.length - tailLen;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (fits('${text.substring(0, mid)}$kEllipsis$tail')) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  if (lo == 0 && tailLen > 0) {
    return ellipsizeMiddle(text, fits, keepTail: tailLen ~/ 2);
  }

  return '${text.substring(0, lo)}$kEllipsis$tail';
}

int fileNameTailLength(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot > 0 ? name.length - dot : 0;

  return ext + 6 > name.length ~/ 2 ? ext : ext + 6;
}

TextFits textFits({
  required TextStyle style,
  required TextScaler scaler,
  required double maxWidth,
  int maxLines = 1,
}) {
  return (text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      textScaler: scaler,
    )..layout(maxWidth: maxLines == 1 ? double.infinity : maxWidth);
    final fits = maxLines == 1 ? tp.width <= maxWidth : !tp.didExceedMaxLines;
    tp.dispose();

    return fits;
  };
}
