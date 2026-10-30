import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waydir/core/models/file_entry.dart';
import 'package:waydir/features/quick_look/quick_look_io.dart';
import 'package:waydir/features/quick_look/text_encoding.dart';

Uint8List _utf16(String text, Endian endian, {required bool bom}) {
  final units = [if (bom) 0xFEFF, ...text.codeUnits];
  final data = ByteData(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    data.setUint16(i * 2, units[i], endian);
  }

  return data.buffer.asUint8List();
}

void main() {
  const sample = '[Cursors]\r\n14,8_28x15=日本語\r\n';

  group('detectUtf16', () {
    test('detects a UTF-16LE BOM', () {
      expect(detectUtf16(_utf16(sample, Endian.little, bom: true)), (
        encoding: TextEncoding.utf16le,
        bom: true,
      ));
    });

    test('detects a UTF-16BE BOM', () {
      expect(detectUtf16(_utf16(sample, Endian.big, bom: true)), (
        encoding: TextEncoding.utf16be,
        bom: true,
      ));
    });

    test('detects BOM-less UTF-16LE from NUL parity', () {
      expect(detectUtf16(_utf16(sample, Endian.little, bom: false)), (
        encoding: TextEncoding.utf16le,
        bom: false,
      ));
    });

    test('ignores UTF-8 text', () {
      expect(detectUtf16(Uint8List.fromList('[a]\nb=1\n'.codeUnits)), isNull);
    });

    test('ignores binary with NULs on both parities', () {
      expect(detectUtf16(Uint8List.fromList([1, 0, 0, 2, 0, 0, 3, 4])), isNull);
    });
  });

  group('round trip', () {
    for (final format in <TextFormat>[
      (encoding: TextEncoding.utf16le, bom: true),
      (encoding: TextEncoding.utf16le, bom: false),
      (encoding: TextEncoding.utf16be, bom: true),
      utf8Format,
    ]) {
      test('$format', () {
        final bytes = encodeText(sample, format);
        expect(decodeText(bytes, format), sample);
      });
    }

    test('encode reproduces the original UTF-16LE file bytes', () {
      final original = _utf16(sample, Endian.little, bom: true);
      final format = detectUtf16(original)!;
      expect(encodeText(decodeText(original, format), format), original);
    });
  });

  group('probeFile', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ql_encoding'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileEntry entryFor(String name, List<int> bytes) {
      final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);

      return FileEntry(
        name: name,
        path: file.path,
        type: FileItemType.file,
        size: bytes.length,
        modified: DateTime.now(),
      );
    }

    test('reads a UTF-16LE ini as text', () async {
      final probe = await probeFile(
        entryFor('a.ini', _utf16(sample, Endian.little, bom: true)),
      );
      expect(probe.kind, QlKind.text);
      expect(probe.text, sample);
      expect(probe.format, (encoding: TextEncoding.utf16le, bom: true));
    });

    test('still treats real binary as binary', () async {
      final probe = await probeFile(
        entryFor('a.conf', [0x7F, 0x45, 0x4C, 0x46, 0, 0, 1, 2, 3, 0, 0, 0]),
      );
      expect(probe.kind, QlKind.binary);
    });

    test('isLikelyTextFile accepts UTF-8 and UTF-16 text', () async {
      expect(
        await isLikelyTextFile(entryFor('a.txt', 'hello\n'.codeUnits)),
        true,
      );
      expect(
        await isLikelyTextFile(
          entryFor('b.ini', _utf16(sample, Endian.little, bom: true)),
        ),
        true,
      );
    });

    test('isLikelyTextFile rejects binary content and extensions', () async {
      expect(
        await isLikelyTextFile(entryFor('a.conf', [0x7F, 0x45, 0, 0, 1, 2])),
        false,
      );
      expect(
        await isLikelyTextFile(entryFor('a.xlsx', 'text'.codeUnits)),
        false,
      );
    });
  });
}
