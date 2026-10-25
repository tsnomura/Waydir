import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../../core/fs/sftp_fs.dart';
import '../../core/logging/app_logger.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import 'quick_look_common.dart';
import 'text_encoding.dart';

typedef QlSection = ({String title, List<MapEntry<String, String>> rows});

class FolderStats {
  final int bytes;
  final int items;
  final bool done;

  const FolderStats(this.bytes, this.items, {required this.done});
}

enum QlKind { text, binary, tooLarge, error }

class Probe {
  final QlKind kind;
  final String text;
  final String? note;
  final TextFormat format;

  const Probe(this.kind, {this.text = '', this.note, this.format = utf8Format});
}

Future<Uint8List> readHead(String path, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  final stream = PlatformPaths.isSftpUri(path)
      ? await const SftpFs().openRead(path, start: 0, end: maxBytes)
      : File(path).openRead(0, maxBytes);
  await for (final chunk in stream) {
    builder.add(chunk);
  }

  return builder.takeBytes();
}

Future<QlSection?> imageInfo(FileEntry e) async {
  if (e.type == FileItemType.folder) return null;
  if (!imageExts.contains(e.extension)) return null;
  final rows = <MapEntry<String, String>>[];
  try {
    final bytes = await readHead(e.realPath, 512 * 1024);
    final tags = await readExifFromBytes(bytes);
    String? tag(String k) {
      final v = tags[k]?.printable.trim();

      return (v == null || v.isEmpty) ? null : v;
    }

    final w = tag('EXIF ExifImageWidth') ?? tag('Image ImageWidth');
    final h = tag('EXIF ExifImageLength') ?? tag('Image ImageLength');
    if (w != null && h != null) {
      rows.add(MapEntry(t.quickLook.dimensions, '$w × $h'));
    }
    final make = tag('Image Make');
    final model = tag('Image Model');
    final cam = [make, model].whereType<String>().join(' ');
    if (cam.isNotEmpty) rows.add(MapEntry(t.quickLook.camera, cam));
    final lens = tag('EXIF LensModel');
    if (lens != null) rows.add(MapEntry(t.quickLook.lens, lens));
    final exp = tag('EXIF ExposureTime');
    if (exp != null) rows.add(MapEntry(t.quickLook.exposure, '$exp s'));
    final fnum = tag('EXIF FNumber');
    if (fnum != null) rows.add(MapEntry(t.quickLook.aperture, 'f/$fnum'));
    final iso = tag('EXIF ISOSpeedRatings');
    if (iso != null) rows.add(MapEntry(t.quickLook.iso, iso));
    final fl = tag('EXIF FocalLength');
    if (fl != null) rows.add(MapEntry(t.quickLook.focalLength, '$fl mm'));
    final dt = tag('EXIF DateTimeOriginal');
    if (dt != null) rows.add(MapEntry(t.quickLook.dateTaken, dt));
  } catch (e, st) {
    log.warn('quick-look', 'image metadata read failed', error: e, stack: st);

    return null;
  }
  if (rows.isEmpty) return null;

  return (title: t.quickLook.sectionImage, rows: rows);
}

Future<Probe> probeFile(FileEntry entry) async {
  try {
    final builder = BytesBuilder(copy: false);
    final stream = PlatformPaths.isSftpUri(entry.realPath)
        ? await const SftpFs().openRead(
            entry.realPath,
            start: 0,
            end: maxTextBytes + 1,
          )
        : File(entry.realPath).openRead(0, maxTextBytes + 1);
    await for (final chunk in stream) {
      builder.add(chunk);
      if (builder.length > maxTextBytes) break;
    }
    final bytes = builder.takeBytes();
    if (bytes.length > maxTextBytes) {
      return Probe(QlKind.tooLarge, note: t.quickLook.tooLarge);
    }
    final utf16 = detectUtf16(bytes);
    if (utf16 != null) {
      final text = decodeText(bytes, utf16);
      if (_looksBinary(text.codeUnits)) return const Probe(QlKind.binary);

      return Probe(QlKind.text, text: text, format: utf16);
    }
    if (_looksBinary(bytes)) return const Probe(QlKind.binary);

    return Probe(QlKind.text, text: utf8.decode(bytes, allowMalformed: true));
  } catch (e, st) {
    log.warn('quick-look', 'file preview read failed', error: e, stack: st);

    return Probe(QlKind.error, note: t.quickLook.readError);
  }
}

bool _looksBinary(List<int> units) {
  final scanLen = units.length > 8000 ? 8000 : units.length;
  var suspicious = 0;
  for (var i = 0; i < scanLen; i++) {
    final u = units[i];
    if (u == 0) return true;
    if (u < 9 || (u > 13 && u < 32) || u == 127) suspicious++;
  }

  return scanLen > 0 && suspicious / scanLen > 0.1;
}
