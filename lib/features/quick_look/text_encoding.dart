import 'dart:convert';
import 'dart:typed_data';

enum TextEncoding { utf8, utf16le, utf16be }

typedef TextFormat = ({TextEncoding encoding, bool bom});

const TextFormat utf8Format = (encoding: TextEncoding.utf8, bom: false);

TextFormat? detectUtf16(Uint8List bytes) {
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (encoding: TextEncoding.utf16le, bom: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (encoding: TextEncoding.utf16be, bom: true);
    }
  }
  final scanLen = (bytes.length > 8000 ? 8000 : bytes.length) & ~1;
  if (scanLen < 4) return null;
  var evenNul = 0;
  var oddNul = 0;
  for (var i = 0; i < scanLen; i += 2) {
    if (bytes[i] == 0) evenNul++;
    if (bytes[i + 1] == 0) oddNul++;
  }
  final pairs = scanLen ~/ 2;
  if (evenNul == 0 && oddNul > pairs * 0.3) {
    return (encoding: TextEncoding.utf16le, bom: false);
  }
  if (oddNul == 0 && evenNul > pairs * 0.3) {
    return (encoding: TextEncoding.utf16be, bom: false);
  }

  return null;
}

Endian _endian(TextEncoding encoding) =>
    encoding == TextEncoding.utf16le ? Endian.little : Endian.big;

String decodeText(Uint8List bytes, TextFormat format) {
  if (format.encoding == TextEncoding.utf8) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  final endian = _endian(format.encoding);
  final data = ByteData.sublistView(bytes);
  final start = format.bom ? 2 : 0;
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(data.getUint16(i, endian));
  }

  return String.fromCharCodes(units);
}

Uint8List encodeText(String text, TextFormat format) {
  if (format.encoding == TextEncoding.utf8) {
    return Uint8List.fromList(utf8.encode(text));
  }
  final endian = _endian(format.encoding);
  final units = text.codeUnits;
  final start = format.bom ? 2 : 0;
  final out = Uint8List(start + units.length * 2);
  final data = ByteData.sublistView(out);
  if (format.bom) data.setUint16(0, 0xFEFF, endian);
  for (var i = 0; i < units.length; i++) {
    data.setUint16(start + i * 2, units[i], endian);
  }

  return out;
}
