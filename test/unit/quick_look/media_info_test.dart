import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/features/quick_look/media_info.dart';

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _le32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _chunk(String type, List<int> data) => [
  ..._be32(data.length),
  ...type.codeUnits,
  ...data,
  0,
  0,
  0,
  0,
];

Uint8List _png({
  required int bits,
  required int colorType,
  int interlace = 0,
  int? ppm,
}) {
  return Uint8List.fromList([
    0x89,
    ...'PNG'.codeUnits,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ..._chunk('IHDR', [
      ..._be32(1920),
      ..._be32(1080),
      bits,
      colorType,
      0,
      0,
      interlace,
    ]),
    if (ppm != null) ..._chunk('pHYs', [..._be32(ppm), ..._be32(ppm), 1]),
    ..._chunk('IDAT', [0]),
  ]);
}

Map<String, String> _rows(MediaRows rows) => {
  for (final r in rows) r.key: r.value,
};

void main() {
  group('parseImageHeader', () {
    test('PNG: size, color type, bit depth and pHYs dpi', () {
      final h = parseImageHeader(_png(bits: 16, colorType: 6, ppm: 11811))!;
      expect(_rows(imageHeaderRows(h)), {
        'Dimensions': '1920 × 1080',
        'Format': 'PNG',
        'Color': 'RGBA · 16-bit',
        'Resolution': '300 dpi',
      });
    });

    test('PNG: palette, interlaced, no pHYs', () {
      final h = parseImageHeader(_png(bits: 8, colorType: 3, interlace: 1))!;
      final rows = _rows(imageHeaderRows(h));
      expect(rows['Format'], 'PNG (interlaced)');
      expect(rows['Color'], 'Palette · 8-bit');
      expect(rows.containsKey('Resolution'), isFalse);
    });

    test('JPEG: JFIF density and progressive SOF', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xE0, 0x00, 0x10, ...'JFIF'.codeUnits, 0, 1, 1, 1,
        0x00, 0x48, 0x00, 0x96, 0, 0,
        0xFF, 0xC2, 0x00, 0x11, 8, 0x01, 0xE0, 0x02, 0x80, 3,
        1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
      ]);
      final rows = _rows(imageHeaderRows(parseImageHeader(bytes)!));
      expect(rows['Dimensions'], '640 × 480');
      expect(rows['Format'], 'JPEG (progressive)');
      expect(rows['Color'], 'YCbCr · 8-bit');
      expect(rows['Resolution'], '72 × 150 dpi');
    });

    test('JPEG: dots per cm become dpi, grayscale', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8,
        0xFF, 0xE0, 0x00, 0x10, ...'JFIF'.codeUnits, 0, 1, 1, 2,
        0x00, 0x76, 0x00, 0x76, 0, 0,
        0xFF, 0xC0, 0x00, 0x0B, 12, 0x00, 0x10, 0x00, 0x20, 1, 1, 0x11, 0,
      ]);
      final rows = _rows(imageHeaderRows(parseImageHeader(bytes)!));
      expect(rows['Dimensions'], '32 × 16');
      expect(rows['Format'], 'JPEG');
      expect(rows['Color'], 'Gray · 12-bit');
      expect(rows['Resolution'], '299.7 dpi');
    });

    test('GIF: palette size from the global color table', () {
      final bytes = Uint8List.fromList([
        ...'GIF89a'.codeUnits,
        ..._le16(100),
        ..._le16(50),
        0xF7,
        0,
        0,
      ]);
      final rows = _rows(imageHeaderRows(parseImageHeader(bytes)!));
      expect(rows['Dimensions'], '100 × 50');
      expect(rows['Color'], 'Palette · 256 colors');
    });

    test('BMP: bottom-up height, 24 bpp, pixels per metre', () {
      final bytes = Uint8List.fromList([
        ...'BM'.codeUnits,
        ..._le32(0),
        ..._le32(0),
        ..._le32(54),
        ..._le32(40),
        ..._le32(800),
        ..._le32(-600),
        ..._le16(1),
        ..._le16(24),
        ..._le32(0),
        ..._le32(0),
        ..._le32(2835),
        ..._le32(2835),
        ..._le32(0),
        ..._le32(0),
      ]);
      final rows = _rows(imageHeaderRows(parseImageHeader(bytes)!));
      expect(rows['Dimensions'], '800 × 600');
      expect(rows['Color'], 'RGB · 8-bit');
      expect(rows['Resolution'], '72 dpi');
    });

    test('WebP: lossless with alpha', () {
      const w = 1000;
      const h = 500;
      final v = (w - 1) | ((h - 1) << 14) | (1 << 28);
      final bytes = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        ..._le32(0),
        ...'WEBP'.codeUnits,
        ...'VP8L'.codeUnits,
        ..._le32(0),
        0x2F,
        ..._le32(v),
        0,
        0,
        0,
        0,
      ]);
      final rows = _rows(imageHeaderRows(parseImageHeader(bytes)!));
      expect(rows['Dimensions'], '1000 × 500');
      expect(rows['Format'], 'WebP (lossless)');
      expect(rows['Color'], 'RGBA · 8-bit');
    });

    test('unknown or truncated data gives null', () {
      expect(parseImageHeader(Uint8List.fromList([1, 2, 3])), isNull);
      expect(parseImageHeader(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isNull);
      expect(parseImageHeader(_png(bits: 8, colorType: 2).sublist(0, 20)),
          isNull);
    });
  });

  test('pixelFormatBits', () {
    expect(pixelFormatBits('yuv420p'), 8);
    expect(pixelFormatBits('yuvj422p'), 8);
    expect(pixelFormatBits('yuv420p10le'), 10);
    expect(pixelFormatBits('p010le'), 10);
    expect(pixelFormatBits('gray16be'), 16);
    expect(pixelFormatBits('rgb24'), 8);
    expect(pixelFormatBits('rgb48be'), 16);
    expect(pixelFormatBits('gbrpf32le'), 32);
    expect(pixelFormatBits('monob'), 1);
    expect(pixelFormatBits('something'), isNull);
  });

  test('formatMediaDuration', () {
    expect(formatMediaDuration(3.003), '3 s');
    expect(formatMediaDuration(2.5), '2.5 s');
    expect(formatMediaDuration(75.4), '1:15');
    expect(formatMediaDuration(3725), '1:02:05');
  });

  group('ffprobeRows', () {
    final video = {
      'streams': [
        {
          'codec_type': 'video',
          'codec_name': 'h264',
          'profile': 'High 10',
          'width': 640,
          'height': 360,
          'pix_fmt': 'yuv420p10le',
          'r_frame_rate': '30000/1001',
          'avg_frame_rate': '30000/1001',
          'bits_per_raw_sample': '10',
          'disposition': {'attached_pic': 0},
        },
        {
          'codec_type': 'audio',
          'codec_name': 'aac',
          'profile': 'LC',
          'sample_rate': '48000',
          'channel_layout': 'stereo',
          'disposition': {'attached_pic': 0},
        },
      ],
      'format': {'duration': '3.003000', 'bit_rate': '943960'},
    };

    test('video', () {
      expect(_rows(ffprobeRows(video, MediaKind.video)), {
        'Dimensions': '640 × 360',
        'Duration': '3 s',
        'Frame rate': '29.97 fps',
        'Video': 'H264 · High 10',
        'Pixel format': 'yuv420p10le · 10-bit',
        'Bitrate': '944 kbps',
        'Audio': 'AAC · LC · 48 kHz · stereo',
      });
    });

    test('audio with tags, ignoring cover art', () {
      final audio = {
        'streams': [
          {
            'codec_type': 'audio',
            'codec_name': 'flac',
            'sample_rate': '44100',
            'channels': 1,
            'bits_per_raw_sample': '16',
            'disposition': {'attached_pic': 0},
          },
          {
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'width': 500,
            'height': 500,
            'disposition': {'attached_pic': 1},
          },
        ],
        'format': {
          'duration': '200.5',
          'bit_rate': '1411200',
          'tags': {'TITLE': 'Test Tone', 'ARTIST': 'Waydir', 'album': ' '},
        },
      };
      expect(_rows(ffprobeRows(audio, MediaKind.audio)), {
        'Duration': '3:21',
        'Codec': 'FLAC',
        'Sample rate': '44.1 kHz',
        'Channels': '1 ch',
        'Bit depth': '16-bit',
        'Bitrate': '1.41 Mbps',
        'Title': 'Test Tone',
        'Artist': 'Waydir',
      });
    });

    test('image', () {
      final image = {
        'streams': [
          {
            'codec_type': 'video',
            'codec_name': 'tiff',
            'width': 320,
            'height': 200,
            'pix_fmt': 'rgb48be',
          },
        ],
        'format': <String, dynamic>{},
      };
      expect(_rows(ffprobeRows(image, MediaKind.image)), {
        'Dimensions': '320 × 200',
        'Format': 'TIFF',
        'Pixel format': 'rgb48be · 16-bit',
      });
    });

    test('missing streams give no rows', () {
      expect(ffprobeRows({'streams': []}, MediaKind.image), isEmpty);
    });
  });
}
