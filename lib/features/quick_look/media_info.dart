import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import 'quick_look_common.dart';
import 'quick_look_io.dart';

typedef MediaRows = List<MapEntry<String, String>>;

const probedImageExts = {
  'tif',
  'tiff',
  'heic',
  'heif',
  'avif',
  'ico',
  'tga',
  'exr',
  'jxl',
  'dds',
  'psd',
};

const mediaVideoExts = {
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'webm',
  'avi',
  'wmv',
  'flv',
  'mpg',
  'mpeg',
  'ts',
  'm2ts',
  'mts',
  '3gp',
  'ogv',
};

const mediaAudioExts = {
  'mp3',
  'wav',
  'flac',
  'ogg',
  'oga',
  'm4a',
  'aac',
  'wma',
  'opus',
  'aif',
  'aiff',
  'ape',
  'alac',
};

class ImageHeader {
  final String format;
  final int width;
  final int height;
  final String color;
  final int? bits;
  final int? paletteColors;
  final bool progressive;
  final double? dpiX;
  final double? dpiY;

  const ImageHeader({
    required this.format,
    required this.width,
    required this.height,
    required this.color,
    this.bits,
    this.paletteColors,
    this.progressive = false,
    this.dpiX,
    this.dpiY,
  });
}

int _be16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _le16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _le24(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);

bool _ascii(Uint8List b, int o, String s) {
  if (o + s.length > b.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[o + i] != s.codeUnitAt(i)) return false;
  }

  return true;
}

ImageHeader? parseImageHeader(Uint8List b) {
  try {
    if (b.length >= 24 && _ascii(b, 1, 'PNG') && _ascii(b, 12, 'IHDR')) {
      return _png(b);
    }
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) return _jpeg(b);
    if (b.length >= 13 && _ascii(b, 0, 'GIF8')) return _gif(b);
    if (b.length >= 30 && _ascii(b, 0, 'BM')) return _bmp(b);
    if (b.length >= 25 && _ascii(b, 0, 'RIFF') && _ascii(b, 8, 'WEBP')) {
      return _webp(b);
    }
  } on RangeError {
    return null;
  }

  return null;
}

ImageHeader _png(Uint8List b) {
  final width = _be32(b, 16);
  final height = _be32(b, 20);
  final bits = b[24];
  final colorType = b[25];
  final color = switch (colorType) {
    0 => 'Gray',
    2 => 'RGB',
    3 => 'Palette',
    4 => 'Gray + alpha',
    6 => 'RGBA',
    _ => 'Unknown',
  };
  double? dpiX;
  double? dpiY;
  var o = 8;
  while (o + 8 <= b.length) {
    final length = _be32(b, o);
    if (_ascii(b, o + 4, 'IDAT') || _ascii(b, o + 4, 'IEND')) break;
    if (_ascii(b, o + 4, 'pHYs') && o + 17 <= b.length && b[o + 16] == 1) {
      dpiX = _be32(b, o + 8) * 0.0254;
      dpiY = _be32(b, o + 12) * 0.0254;
    }
    o += 12 + length;
  }

  return ImageHeader(
    format: 'PNG',
    width: width,
    height: height,
    color: color,
    bits: bits,
    progressive: b[28] == 1,
    dpiX: dpiX,
    dpiY: dpiY,
  );
}

ImageHeader? _jpeg(Uint8List b) {
  var o = 2;
  double? dpiX;
  double? dpiY;
  while (o + 4 <= b.length) {
    if (b[o] != 0xFF) {
      o++;
      continue;
    }
    final marker = b[o + 1];
    if (marker == 0xFF) {
      o++;
      continue;
    }
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7)) {
      o += 2;
      continue;
    }
    final length = _be16(b, o + 2);
    if (marker == 0xE0 && _ascii(b, o + 4, 'JFIF') && o + 16 <= b.length) {
      final units = b[o + 11];
      final x = _be16(b, o + 12).toDouble();
      final y = _be16(b, o + 14).toDouble();
      if (units == 1) {
        dpiX = x;
        dpiY = y;
      } else if (units == 2) {
        dpiX = x * 2.54;
        dpiY = y * 2.54;
      }
    }
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof && o + 10 <= b.length) {
      final components = b[o + 9];

      return ImageHeader(
        format: 'JPEG',
        width: _be16(b, o + 7),
        height: _be16(b, o + 5),
        color: switch (components) {
          1 => 'Gray',
          3 => 'YCbCr',
          4 => 'CMYK',
          _ => '$components channels',
        },
        bits: b[o + 4],
        progressive: marker == 0xC2 || marker == 0xC6 || marker == 0xCA,
        dpiX: dpiX,
        dpiY: dpiY,
      );
    }
    if (marker == 0xDA) break;
    o += 2 + length;
  }

  return null;
}

ImageHeader _gif(Uint8List b) {
  final packed = b[10];
  final hasTable = packed & 0x80 != 0;

  return ImageHeader(
    format: 'GIF',
    width: _le16(b, 6),
    height: _le16(b, 8),
    color: 'Palette',
    paletteColors: hasTable ? 1 << ((packed & 0x07) + 1) : null,
  );
}

ImageHeader _bmp(Uint8List b) {
  final header = _le32(b, 14);
  final int width;
  final int height;
  final int bpp;
  if (header == 12) {
    width = _le16(b, 18);
    height = _le16(b, 20);
    bpp = _le16(b, 24);
  } else {
    width = _le32(b, 18).toSigned(32);
    height = _le32(b, 22).toSigned(32).abs();
    bpp = _le16(b, 28);
  }
  double? dpiX;
  double? dpiY;
  if (header >= 40 && b.length >= 46) {
    final x = _le32(b, 38);
    final y = _le32(b, 42);
    if (x > 0 && y > 0) {
      dpiX = x * 0.0254;
      dpiY = y * 0.0254;
    }
  }

  return ImageHeader(
    format: 'BMP',
    width: width,
    height: height,
    color: bpp <= 8
        ? 'Palette'
        : bpp == 32
        ? 'RGBA'
        : 'RGB',
    bits: bpp <= 8 ? bpp : (bpp == 16 ? 5 : 8),
    dpiX: dpiX,
    dpiY: dpiY,
  );
}

ImageHeader? _webp(Uint8List b) {
  if (_ascii(b, 12, 'VP8X')) {
    final alpha = b[20] & 0x10 != 0;

    return ImageHeader(
      format: 'WebP',
      width: _le24(b, 24) + 1,
      height: _le24(b, 27) + 1,
      color: alpha ? 'RGBA' : 'RGB',
      bits: 8,
    );
  }
  if (_ascii(b, 12, 'VP8L') && b[20] == 0x2F) {
    final v = _le32(b, 21);

    return ImageHeader(
      format: 'WebP (lossless)',
      width: (v & 0x3FFF) + 1,
      height: ((v >> 14) & 0x3FFF) + 1,
      color: (v >> 28) & 1 == 1 ? 'RGBA' : 'RGB',
      bits: 8,
    );
  }
  if (_ascii(b, 12, 'VP8 ') && b[23] == 0x9D && b[24] == 0x01) {
    return ImageHeader(
      format: 'WebP (lossy)',
      width: _le16(b, 26) & 0x3FFF,
      height: _le16(b, 28) & 0x3FFF,
      color: 'RGB',
      bits: 8,
    );
  }

  return null;
}

String _trimNum(double v, int decimals) {
  final s = v.toStringAsFixed(decimals);
  if (!s.contains('.')) return s;

  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _dpi(double x, double y) {
  final rx = _trimNum(x, 1);
  final ry = _trimNum(y, 1);

  return rx == ry ? '$rx dpi' : '$rx × $ry dpi';
}

MediaRows imageHeaderRows(ImageHeader h) {
  final color = StringBuffer(h.color);
  if (h.paletteColors != null) {
    color.write(' · ${h.paletteColors} colors');
  } else if (h.bits != null) {
    color.write(' · ${h.bits}-bit');
  }
  final format = h.progressive
      ? '${h.format} (${h.format == 'PNG' ? 'interlaced' : 'progressive'})'
      : h.format;

  return [
    MapEntry(t.quickLook.dimensions, '${h.width} × ${h.height}'),
    MapEntry(t.quickLook.mediaFormat, format),
    MapEntry(t.quickLook.colorMode, color.toString()),
    if (h.dpiX != null && h.dpiY != null && h.dpiX! > 0)
      MapEntry(t.quickLook.imageResolution, _dpi(h.dpiX!, h.dpiY!)),
  ];
}

const _packedBits = {
  'rgb24': 8,
  'bgr24': 8,
  'rgba': 8,
  'bgra': 8,
  'argb': 8,
  'abgr': 8,
  'rgb0': 8,
  'bgr0': 8,
  '0rgb': 8,
  '0bgr': 8,
  'gray': 8,
  'ya8': 8,
  'pal8': 8,
  'nv12': 8,
  'nv21': 8,
  'nv16': 8,
  'yuyv422': 8,
  'uyvy422': 8,
  'rgb48le': 16,
  'rgb48be': 16,
  'bgr48le': 16,
  'bgr48be': 16,
  'rgba64le': 16,
  'rgba64be': 16,
  'bgra64le': 16,
  'bgra64be': 16,
  'monob': 1,
  'monow': 1,
};

int? pixelFormatBits(String pixFmt) {
  final known = _packedBits[pixFmt];
  if (known != null) return known;
  if (pixFmt.contains('f32')) return 32;
  if (pixFmt.contains('f16')) return 16;
  final m = RegExp(r'(?:p|gray|ya)(\d+)(?:le|be)?$').firstMatch(pixFmt);
  if (m != null) return int.parse(m.group(1)!);
  if (RegExp(r'^(?:yuvj?|gbr)a?\d*p$').hasMatch(pixFmt)) return 8;

  return null;
}

double? _number(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);

  return null;
}

double? _rate(Object? v) {
  if (v is! String) return null;
  final parts = v.split('/');
  if (parts.length != 2) return double.tryParse(v);
  final n = double.tryParse(parts[0]);
  final d = double.tryParse(parts[1]);
  if (n == null || d == null || d == 0 || n == 0) return null;

  return n / d;
}

String formatMediaDuration(double seconds) {
  if (seconds < 10) return '${_trimNum(seconds, 2)} s';
  final total = seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';

  return '$m:$s';
}

String _bitrate(double bps) {
  if (bps >= 1e6) return '${_trimNum(bps / 1e6, 2)} Mbps';

  return '${(bps / 1e3).round()} kbps';
}

String _sampleRate(double hz) => '${_trimNum(hz / 1000, 1)} kHz';

String _codec(Map<String, dynamic> stream) {
  final name = (stream['codec_name'] as String? ?? '?').toUpperCase();
  final profile = stream['profile'] as String?;
  if (profile == null || profile.isEmpty || profile == 'unknown') return name;

  return '$name · $profile';
}

String _channels(Map<String, dynamic> stream) {
  final layout = stream['channel_layout'] as String?;
  if (layout != null && layout.isNotEmpty) return layout;
  final n = _number(stream['channels'])?.toInt();

  return n == null ? '?' : '$n ch';
}

String? _pixelFormat(Map<String, dynamic> stream) {
  final pixFmt = stream['pix_fmt'] as String?;
  if (pixFmt == null || pixFmt.isEmpty) return null;
  final raw = _number(stream['bits_per_raw_sample'])?.toInt();
  final bits = (raw != null && raw > 0) ? raw : pixelFormatBits(pixFmt);

  return bits == null ? pixFmt : '$pixFmt · $bits-bit';
}

String? _tag(Map<String, dynamic>? tags, String key) {
  if (tags == null) return null;
  for (final entry in tags.entries) {
    if (entry.key.toLowerCase() == key && entry.value is String) {
      final v = (entry.value as String).trim();

      return v.isEmpty ? null : v;
    }
  }

  return null;
}

enum MediaKind { image, video, audio }

MediaRows ffprobeRows(Map<String, dynamic> json, MediaKind kind) {
  final streams = (json['streams'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  final format = json['format'] as Map<String, dynamic>? ?? const {};
  Map<String, dynamic>? video;
  Map<String, dynamic>? audio;
  for (final s in streams) {
    final type = s['codec_type'];
    final cover =
        (s['disposition'] as Map<String, dynamic>?)?['attached_pic'] == 1;
    if (type == 'video' && !cover) video ??= s;
    if (type == 'audio') audio ??= s;
  }
  final rows = <MapEntry<String, String>>[];
  void add(String label, String? value) {
    if (value != null && value.isNotEmpty) rows.add(MapEntry(label, value));
  }

  final duration = _number(format['duration']);
  final bitrate = _number(format['bit_rate']);
  final ql = t.quickLook;

  switch (kind) {
    case MediaKind.image:
      if (video == null) return rows;
      add(ql.dimensions, '${video['width']} × ${video['height']}');
      add(ql.mediaFormat, (video['codec_name'] as String?)?.toUpperCase());
      add(ql.pixelFormat, _pixelFormat(video));
    case MediaKind.video:
      if (video != null) {
        add(ql.dimensions, '${video['width']} × ${video['height']}');
      }
      if (duration != null) add(ql.duration, formatMediaDuration(duration));
      if (video != null) {
        final fps =
            _rate(video['avg_frame_rate']) ?? _rate(video['r_frame_rate']);
        if (fps != null) add(ql.frameRate, '${_trimNum(fps, 3)} fps');
        add(ql.videoCodec, _codec(video));
        add(ql.pixelFormat, _pixelFormat(video));
      }
      if (bitrate != null) add(ql.bitrate, _bitrate(bitrate));
      if (audio != null) {
        final rate = _number(audio['sample_rate']);
        add(
          ql.audioTrack,
          [
            _codec(audio),
            if (rate != null) _sampleRate(rate),
            _channels(audio),
          ].join(' · '),
        );
      }
    case MediaKind.audio:
      if (duration != null) add(ql.duration, formatMediaDuration(duration));
      if (audio != null) {
        add(ql.codec, _codec(audio));
        final rate = _number(audio['sample_rate']);
        if (rate != null) add(ql.sampleRate, _sampleRate(rate));
        add(ql.channels, _channels(audio));
        final bits =
            _number(audio['bits_per_raw_sample'])?.toInt() ??
            _number(audio['bits_per_sample'])?.toInt();
        if (bits != null && bits > 0) add(ql.bitDepth, '$bits-bit');
      }
      if (bitrate != null) add(ql.bitrate, _bitrate(bitrate));
      final tags = format['tags'] as Map<String, dynamic>?;
      add(ql.mediaTitle, _tag(tags, 'title'));
      add(ql.mediaArtist, _tag(tags, 'artist'));
      add(ql.mediaAlbum, _tag(tags, 'album'));
  }

  return rows;
}

class FfprobeInfo {
  FfprobeInfo._();

  static const _timeout = Duration(seconds: 5);
  static final _cache = <String, Map<String, dynamic>?>{};
  static final _inFlight = <String, Future<Map<String, dynamic>?>>{};

  static Future<Map<String, dynamic>?> probe(FileEntry entry) {
    if (PlatformPaths.isRemoteUri(entry.realPath)) return Future.value(null);
    final key = '${entry.realPath}|${entry.modifiedMs}|${entry.size}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);

    return _inFlight.putIfAbsent(key, () async {
      try {
        final result = await _run(entry.realPath);
        _cache[key] = result;

        return result;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  static Future<Map<String, dynamic>?> _run(String path) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_format',
        '-show_streams',
        '-of',
        'json',
        path,
      ], stdoutEncoding: utf8).timeout(_timeout);
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String);

      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e, st) {
      log.warn('quick-look', 'ffprobe failed for $path', error: e, stack: st);

      return null;
    }
  }
}

MediaKind? mediaKindOf(FileEntry e) {
  if (e.type == FileItemType.folder) return null;
  final ext = e.extension;
  if (imageExts.contains(ext) || probedImageExts.contains(ext)) {
    return MediaKind.image;
  }
  if (mediaVideoExts.contains(ext)) return MediaKind.video;
  if (mediaAudioExts.contains(ext)) return MediaKind.audio;

  return null;
}

Future<MediaRows> _imageBasics(FileEntry e) async {
  if (imageExts.contains(e.extension)) {
    try {
      final header = parseImageHeader(await readHead(e.realPath, 256 * 1024));
      if (header != null) return imageHeaderRows(header);
    } catch (err, st) {
      log.warn('quick-look', 'image header read failed', error: err, stack: st);
    }
  }
  final json = await FfprobeInfo.probe(e);

  return json == null ? const [] : ffprobeRows(json, MediaKind.image);
}

Future<QlSection?> mediaInfo(FileEntry e) async {
  final kind = mediaKindOf(e);
  switch (kind) {
    case null:
      return null;
    case MediaKind.image:
      final basics = await _imageBasics(e);
      final exif = imageExts.contains(e.extension) ? await imageInfo(e) : null;
      final hasDimensions = basics.any((r) => r.key == t.quickLook.dimensions);
      final rows = [
        ...basics,
        for (final row in exif?.rows ?? const <MapEntry<String, String>>[])
          if (!(hasDimensions && row.key == t.quickLook.dimensions)) row,
      ];

      return rows.isEmpty
          ? null
          : (title: t.quickLook.sectionImage, rows: rows);
    case MediaKind.video:
    case MediaKind.audio:
      final json = await FfprobeInfo.probe(e);
      if (json == null) return null;
      final rows = ffprobeRows(json, kind);
      if (rows.isEmpty) return null;

      return (
        title: kind == MediaKind.video
            ? t.quickLook.sectionVideo
            : t.quickLook.sectionAudio,
        rows: rows,
      );
  }
}
