import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:waydir/core/archive/archive_reader.dart';

Uint8List _payload(int size, int seed) {
  final random = Random(seed);

  return Uint8List.fromList(List.generate(size, (_) => random.nextInt(256)));
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }

    return i;
  }

  return -1;
}

void main() {
  late Directory tmp;
  final stored = _payload(3 * 1024 * 1024 + 123, 1);
  final deflated = Uint8List.fromList(
    List.generate(2 * 1024 * 1024 + 7, (i) => i % 251),
  );

  setUp(() => tmp = Directory.systemTemp.createTempSync('waydir_arc_stream'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeZip(Uint8List bytes) {
    final path = p.join(tmp.path, 'sample.zip');
    File(path).writeAsBytesSync(bytes);

    return path;
  }

  Uint8List encode() {
    final archive = Archive()
      ..add(ArchiveFile.noCompress('big.bin', stored.length, stored))
      ..add(ArchiveFile.bytes('dir/text.bin', deflated));

    return ZipEncoder().encodeBytes(archive);
  }

  test('extracts stored and deflated entries larger than one chunk', () {
    final zip = writeZip(encode());
    final out = p.join(tmp.path, 'out');
    ArchiveReader.extractAll(zip, out);

    expect(File(p.join(out, 'big.bin')).readAsBytesSync(), stored);
    expect(File(p.join(out, 'dir', 'text.bin')).readAsBytesSync(), deflated);
  });

  test('extractEntry streams a single large entry', () {
    final zip = writeZip(encode());
    final dest = p.join(tmp.path, 'single', 'big.bin');
    ArchiveReader.extractEntry(zip, 'big.bin', dest);

    expect(File(dest).readAsBytesSync(), stored);
  });

  test('a corrupted entry fails and leaves no file behind', () {
    final bytes = encode();
    final at = _indexOf(bytes, Uint8List.sublistView(stored, 0, 64));
    expect(at, greaterThan(0));
    bytes[at + 2 * 1024 * 1024] ^= 0xff;
    final zip = writeZip(bytes);
    final dest = p.join(tmp.path, 'bad', 'big.bin');

    expect(
      () => ArchiveReader.extractEntry(zip, 'big.bin', dest),
      throwsA(isA<ArchiveReadException>()),
    );
    expect(File(dest).existsSync(), isFalse);
  });
}
