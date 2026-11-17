import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'drive_model.dart';

typedef _StatvfsNative = Int32 Function(Pointer<Utf8>, Pointer<Uint64>);
typedef _StatvfsDart = int Function(Pointer<Utf8>, Pointer<Uint64>);

const _statvfsWords = 14;
const _frsizeIndex = 1;
const _blocksIndex = 2;
const _availableIndex = 4;

_StatvfsDart? _loadStatvfs() {
  try {
    return DynamicLibrary.process()
        .lookupFunction<_StatvfsNative, _StatvfsDart>('statvfs');
  } catch (_) {
    return null;
  }
}

final _statvfs = _loadStatvfs();

bool get statvfsAvailable =>
    Platform.isLinux && _statvfs != null && sizeOf<IntPtr>() == 8;

DriveSpace? statvfsSpace(String path) {
  final statvfs = _statvfs;
  if (!statvfsAvailable || statvfs == null) return null;
  final nativePath = path.toNativeUtf8();
  final buf = calloc<Uint64>(_statvfsWords);
  try {
    if (statvfs(nativePath, buf) != 0) return null;
    final frsize = buf[_frsizeIndex];
    final blocks = buf[_blocksIndex];
    if (frsize <= 0 || blocks <= 0) return null;

    return DriveSpace(
      totalBytes: blocks * frsize,
      freeBytes: buf[_availableIndex] * frsize,
    );
  } finally {
    calloc.free(nativePath);
    calloc.free(buf);
  }
}
