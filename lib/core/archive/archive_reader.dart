import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../i18n/strings.g.dart';

class ArchiveReadException implements Exception {
  final String message;
  const ArchiveReadException(this.message);
  @override
  String toString() => message;
}

class ArchiveEntry {
  final String path;
  final int size;
  final bool isDir;
  final int mtimeSeconds;
  final DateTime? modified;
  final bool encrypted;

  const ArchiveEntry({
    required this.path,
    required this.size,
    required this.isDir,
    required this.mtimeSeconds,
    this.modified,
    this.encrypted = false,
  });
}

class _CheckedFileSink extends OutputStream {
  static const _bufferSize = 1024 * 1024;

  final RandomAccessFile _file;
  final Uint8List _buffer = Uint8List(_bufferSize);
  int _buffered = 0;
  int written = 0;
  int crc = 0;

  _CheckedFileSink(this._file) : super(byteOrder: ByteOrder.littleEndian);

  @override
  int get length => written;

  @override
  void writeByte(int value) {
    if (_buffered == _bufferSize) flush();
    _buffer[_buffered++] = value;
    written++;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (_buffered + count > _bufferSize) flush();
    if (count > _bufferSize) {
      crc = getCrc32(
        count == bytes.length ? bytes : bytes.sublist(0, count),
        crc,
      );
      _file.writeFromSync(bytes, 0, count);
    } else {
      _buffer.setRange(_buffered, _buffered + count, bytes);
      _buffered += count;
    }
    written += count;
  }

  @override
  void writeStream(InputStream stream) {
    var remaining = stream.length;
    while (remaining > 0) {
      final count = remaining < _bufferSize ? remaining : _bufferSize;
      writeBytes(stream.readBytes(count).toUint8List());
      remaining -= count;
    }
  }

  @override
  void flush() {
    if (_buffered == 0) return;
    final chunk = Uint8List.sublistView(_buffer, 0, _buffered);
    crc = getCrc32(chunk, crc);
    _file.writeFromSync(chunk);
    _buffered = 0;
  }

  @override
  void clear() {
    _buffered = 0;
  }

  @override
  void closeSync() {
    flush();
    _file.closeSync();
  }

  @override
  Uint8List subset(int start, [int? end]) => throw UnsupportedError('subset');
}

class ArchiveReader {
  ArchiveReader._();

  static void _writeEntry(ArchiveFile entry, String dest, String name) {
    final file = File(dest);
    file.parent.createSync(recursive: true);
    final sink = _CheckedFileSink(file.openSync(mode: FileMode.write));
    try {
      entry.writeContent(sink);
    } finally {
      sink.closeSync();
    }
    final expectedCrc = entry.crc32;
    if (sink.written != entry.size ||
        (expectedCrc != null && expectedCrc != 0 && sink.crc != expectedCrc)) {
      try {
        file.deleteSync();
      } on FileSystemException catch (_) {}
      throw ArchiveReadException(t.errors.archiveEntryCorrupt(path: name));
    }
  }

  static String _normalize(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    while (p.startsWith('./')) {
      p = p.substring(2);
    }

    return p;
  }

  static bool _isUnsafe(String path) {
    if (path.startsWith('/')) return true;
    for (final seg in path.split('/')) {
      if (seg == '..') return true;
    }

    return false;
  }

  static bool _isZipLike(String archivePath) {
    final lower = archivePath.toLowerCase();

    return lower.endsWith('.zip') ||
        lower.endsWith('.jar') ||
        lower.endsWith('.war') ||
        lower.endsWith('.apk') ||
        lower.endsWith('.xpi') ||
        lower.endsWith('.whl') ||
        lower.endsWith('.crx') ||
        lower.endsWith('.epub');
  }

  static DateTime? _zipModified(int value) {
    if (value <= 0) return null;
    final year = ((value >> 25) & 0x7f) + 1980;
    final month = (value >> 21) & 0x0f;
    final day = (value >> 16) & 0x1f;
    final hours = (value >> 11) & 0x1f;
    final minutes = (value >> 5) & 0x3f;
    final seconds = (value << 1) & 0x3e;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return DateTime(year, month, day, hours, minutes, seconds);
  }

  static DateTime? _entryModified(String archivePath, ArchiveFile entry) {
    final value = entry.lastModTime;
    if (value <= 0) return null;
    if (_isZipLike(archivePath)) return _zipModified(value);

    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }

  static void _applyModified(File file, DateTime? modified) {
    if (modified == null) return;
    try {
      file.setLastModifiedSync(modified);
    } on FileSystemException catch (_) {
      return;
    }
  }

  static bool isEncrypted(String archivePath) {
    if (!_isZipLike(archivePath)) return false;
    final stream = InputFileStream(archivePath);
    try {
      final dir = ZipDirectory()..read(stream);

      return dir.fileHeaders.any((h) => h.generalPurposeBitFlag & 1 != 0);
    } catch (_) {
      return false;
    } finally {
      stream.closeSync();
    }
  }

  static bool verifyPassword(String archivePath, String password) {
    final stream = InputFileStream(archivePath);
    try {
      final dir = ZipDirectory()..read(stream, password: password);
      final encrypted =
          dir.fileHeaders
              .where(
                (h) =>
                    h.generalPurposeBitFlag & 1 != 0 &&
                    h.file != null &&
                    h.uncompressedSize > 0,
              )
              .toList()
            ..sort((a, b) => a.compressedSize.compareTo(b.compressedSize));
      if (encrypted.isEmpty) return true;

      return encrypted.first.file!.verifyCrc32();
    } catch (_) {
      return false;
    } finally {
      stream.closeSync();
    }
  }

  static T _useArchive<T>(
    String archivePath,
    T Function(Archive) body, {
    String? password,
  }) {
    InputFileStream? stream;
    final Archive archive;
    try {
      final lower = archivePath.toLowerCase();
      if (_isZipLike(archivePath) || lower.endsWith('.tar')) {
        stream = InputFileStream(archivePath);
      }
      archive = _readArchive(archivePath, stream, password);
    } catch (e) {
      stream?.closeSync();
      rethrow;
    }
    try {
      return body(archive);
    } finally {
      stream?.closeSync();
    }
  }

  static Archive _readArchive(
    String archivePath,
    InputFileStream? stream,
    String? password,
  ) {
    final lower = archivePath.toLowerCase();
    try {
      if (_isZipLike(archivePath)) {
        return ZipDecoder().decodeStream(stream!, password: password);
      } else if (lower.endsWith('.tar')) {
        return TarDecoder().decodeStream(stream!);
      }
      final bytes = File(archivePath).readAsBytesSync();
      if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final decoded = GZipDecoder().decodeBytes(bytes);

        return TarDecoder().decodeBytes(decoded);
      } else if (lower.endsWith('.tar.bz2') ||
          lower.endsWith('.tbz2') ||
          lower.endsWith('.tbz')) {
        final decoded = BZip2Decoder().decodeBytes(bytes);

        return TarDecoder().decodeBytes(decoded);
      } else if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
        final decoded = XZDecoder().decodeBytes(bytes);

        return TarDecoder().decodeBytes(decoded);
      }
      throw ArchiveReadException(t.errors.unsupportedArchiveFormat);
    } catch (e) {
      throw ArchiveReadException(t.errors.archiveReadFailed(error: e));
    }
  }

  static List<ArchiveEntry> listEntries(String archivePath) {
    if (_isZipLike(archivePath)) {
      return _listZipEntries(archivePath);
    }

    return _useArchive(
      archivePath,
      (archive) => _listEntries(archivePath, archive),
    );
  }

  static List<ArchiveEntry> _listZipEntries(String archivePath) {
    final stream = InputFileStream(archivePath);
    try {
      final dir = ZipDirectory()..read(stream);
      final entries = <ArchiveEntry>[];
      for (final zfh in dir.fileHeaders) {
        final raw = zfh.filename;
        final isDir = raw.endsWith('/') || raw.endsWith('\\');
        final zf = zfh.file;
        final dos =
            zf != null && (zf.lastModFileDate > 0 || zf.lastModFileTime > 0)
            ? zf.lastModFileDate << 16 | zf.lastModFileTime
            : zfh.lastModifiedFileDate << 16 | zfh.lastModifiedFileTime;
        final modified = _zipModified(dos);
        final name = _normalize(raw);
        if (name.isNotEmpty) {
          entries.add(
            ArchiveEntry(
              path: name,
              size: zfh.uncompressedSize,
              isDir: isDir,
              mtimeSeconds: modified != null
                  ? modified.millisecondsSinceEpoch ~/ 1000
                  : dos,
              modified: modified,
              encrypted: (zfh.generalPurposeBitFlag & 1) != 0,
            ),
          );
        }
      }

      return entries;
    } finally {
      stream.closeSync();
    }
  }

  static List<ArchiveEntry> _listEntries(String archivePath, Archive archive) {
    final entries = <ArchiveEntry>[];
    for (final entry in archive) {
      final raw = entry.name;
      final isDir = !entry.isFile || raw.endsWith('/');
      final modified = _entryModified(archivePath, entry);
      final name = _normalize(raw);
      if (name.isNotEmpty) {
        entries.add(
          ArchiveEntry(
            path: name,
            size: entry.size,
            isDir: isDir,
            mtimeSeconds: modified != null
                ? modified.millisecondsSinceEpoch ~/ 1000
                : entry.lastModTime,
            modified: modified,
          ),
        );
      }
    }

    return entries;
  }

  static void extractEntry(
    String archivePath,
    String innerPath,
    String destPath, {
    String? password,
  }) => _useArchive(
    archivePath,
    (archive) => _extractEntry(archivePath, archive, innerPath, destPath),
    password: password,
  );

  static void _extractEntry(
    String archivePath,
    Archive archive,
    String innerPath,
    String destPath,
  ) {
    final target = _normalize(innerPath);
    var found = false;

    for (final entry in archive) {
      final raw = entry.name;
      if (_normalize(raw) == target) {
        found = true;
        if (entry.isFile) {
          _writeEntry(entry, destPath, target);
          _applyModified(File(destPath), _entryModified(archivePath, entry));
        }
        break;
      }
    }
    if (!found) {
      throw ArchiveReadException(
        t.errors.archiveEntryNotFound(path: innerPath),
      );
    }
  }

  static String extractTree(
    String archivePath,
    String innerPath,
    String stagingDir, {
    String? password,
  }) => _useArchive(
    archivePath,
    (archive) => _extractTree(archivePath, archive, innerPath, stagingDir),
    password: password,
  );

  static String _extractTree(
    String archivePath,
    Archive archive,
    String innerPath,
    String stagingDir,
  ) {
    final target = _normalize(innerPath);
    final baseName = target.contains('/')
        ? target.substring(target.lastIndexOf('/') + 1)
        : target;
    final stagedRoot = p.join(stagingDir, baseName);
    var found = false;

    for (final entry in archive) {
      final raw = entry.name;
      final epath = _normalize(raw);
      String dest;

      if (epath == target) {
        dest = stagedRoot;
      } else if (epath.startsWith('$target/')) {
        dest = p.joinAll([
          stagedRoot,
          ...epath.substring(target.length + 1).split('/'),
        ]);
      } else {
        continue;
      }

      found = true;
      final isDir = !entry.isFile || raw.endsWith('/');
      final modified = _entryModified(archivePath, entry);
      if (isDir) {
        Directory(dest).createSync(recursive: true);
        continue;
      }

      _writeEntry(entry, dest, epath);
      _applyModified(File(dest), modified);
    }

    if (!found) {
      throw ArchiveReadException(
        t.errors.archiveEntryNotFound(path: innerPath),
      );
    }

    return stagedRoot;
  }

  static void extractAll(
    String archivePath,
    String destDir, {
    void Function(String name)? onEntry,
    bool Function()? isCancelled,
  }) {
    extractAllResolved(
      archivePath,
      (epath, isDir) => '$destDir/$epath',
      onEntry: onEntry,
      isCancelled: isCancelled,
    );
  }

  static void extractAllResolved(
    String archivePath,
    String? Function(String epath, bool isDir) resolveDest, {
    void Function(String name)? onEntry,
    bool Function()? isCancelled,
    String? password,
  }) => _useArchive(
    archivePath,
    password: password,
    (archive) => _extractAllResolved(
      archivePath,
      archive,
      resolveDest,
      onEntry: onEntry,
      isCancelled: isCancelled,
    ),
  );

  static void _extractAllResolved(
    String archivePath,
    Archive archive,
    String? Function(String epath, bool isDir) resolveDest, {
    void Function(String name)? onEntry,
    bool Function()? isCancelled,
  }) {
    for (final entry in archive) {
      if (isCancelled != null && isCancelled()) break;

      final raw = entry.name;
      final epath = _normalize(raw);
      if (epath.isEmpty || _isUnsafe(epath)) continue;

      final isDir = !entry.isFile || raw.endsWith('/');
      onEntry?.call(epath);

      final dest = resolveDest(epath, isDir);
      if (dest == null) continue;

      final modified = _entryModified(archivePath, entry);
      if (isDir) {
        Directory(dest).createSync(recursive: true);
        continue;
      }

      _writeEntry(entry, dest, epath);
      _applyModified(File(dest), modified);
    }
  }
}
