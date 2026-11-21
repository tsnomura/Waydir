import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/platform_paths.dart';

class GeneratorCacheLocation {
  GeneratorCacheLocation._();

  static const folderName = '.waydir-cache';
  static const childName = 'generator_cache';

  static const registryName = 'generator_cache_locations.txt';

  static final _dirByAnchor = <String, Future<String?>>{};
  static final _rootByDir = <String, String?>{};
  static final _anchorByDir = <String, String?>{};
  static String? _registry;

  static Future<String> forSource(
    String sourcePath, {
    required String fallback,
  }) async {
    final sourceDir = p.dirname(sourcePath);
    final root = volumeRootOfDirectory(sourceDir);
    if (root == null) return fallback;
    final fallbackRoot = volumeRootOfDirectory(fallback);
    if (fallbackRoot != null && _sameRoot(root, fallbackRoot)) return fallback;
    _registry ??= p.join(p.dirname(fallback), registryName);
    final anchor = Platform.isWindows ? root : _ownedAnchorFor(root, sourceDir);
    if (anchor == null) return fallback;
    final dir = await (_dirByAnchor[_rootKey(anchor)] ??= _prepare(anchor));

    return dir ?? fallback;
  }

  static Future<List<String>> existingDirectories({String? fallback}) async {
    final dirs = <String>{};
    for (final pending in _dirByAnchor.values) {
      final dir = await pending;
      if (dir != null) dirs.add(dir);
    }
    final registry =
        _registry ??
        (fallback == null ? null : p.join(p.dirname(fallback), registryName));
    if (registry != null) {
      try {
        for (final line in await File(registry).readAsLines()) {
          if (line.isNotEmpty && await Directory(line).exists()) dirs.add(line);
        }
      } catch (_) {}
    }
    for (final root in _candidateRoots()) {
      final dir = p.join(root, folderName, childName);
      try {
        if (await Directory(dir).exists()) dirs.add(dir);
      } catch (_) {}
    }

    return dirs.toList();
  }

  static String? _ownedAnchorFor(String root, String dir) {
    if (_anchorByDir.containsKey(dir)) return _anchorByDir[dir];
    final anchor = ownedAnchor(
      root,
      dir,
      uid: _Posix.uid,
      ownerOf: _Posix.ownerOf,
      writable: _Posix.writable,
    );
    _anchorByDir[dir] = anchor;

    return anchor;
  }

  @visibleForTesting
  static String? ownedAnchor(
    String root,
    String dir, {
    required int? uid,
    required int? Function(String path) ownerOf,
    required bool Function(String path) writable,
  }) {
    if (uid == null) return null;
    final normalizedRoot = p.normalize(root);
    final normalizedDir = p.normalize(dir);
    if (normalizedDir != normalizedRoot &&
        !p.isWithin(normalizedRoot, normalizedDir)) {
      return null;
    }
    final candidates = [normalizedRoot];
    if (normalizedDir != normalizedRoot) {
      var current = normalizedRoot;
      for (final part in p.split(
        p.relative(normalizedDir, from: normalizedRoot),
      )) {
        current = p.join(current, part);
        candidates.add(current);
      }
    }
    for (final candidate in candidates) {
      if (ownerOf(candidate) == uid && writable(candidate)) return candidate;
    }

    return null;
  }

  static String? volumeRootOfDirectory(String dir) {
    if (_rootByDir.containsKey(dir)) return _rootByDir[dir];
    final root = _volumeRoot(dir);
    _rootByDir[dir] = root;

    return root;
  }

  static bool _sameRoot(String a, String b) => _rootKey(a) == _rootKey(b);

  static String _rootKey(String root) {
    final trimmed =
        root.length > 1 && (root.endsWith('/') || root.endsWith(r'\'))
        ? root.substring(0, root.length - 1)
        : root;

    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }

  static Future<String?> _prepare(String anchor) async {
    final dir = await prepareIn(anchor);
    if (dir != null) await _register(dir);

    return dir;
  }

  @visibleForTesting
  static Future<String?> prepareIn(String anchor) async {
    final base = p.join(anchor, folderName);
    final dir = p.join(base, childName);
    try {
      if (!Platform.isWindows) {
        await Directory(base).create();
        final uid = _Posix.uid;
        if (uid == null || _Posix.ownerOf(base) != uid) {
          throw StateError('$base is not owned by this user');
        }
        if (!_Posix.restrictToOwner(base)) {
          throw StateError('could not set $base to mode 700');
        }
      }
      await Directory(dir).create(recursive: true);
      final probe = File(p.join(dir, '.write-test-$pid'));
      await probe.writeAsString('');
      await probe.delete();
      if (Platform.isWindows) _markHidden(base);

      return dir;
    } catch (e) {
      log.warn('generators', 'cache in $anchor unavailable, using default: $e');

      return null;
    }
  }

  static Future<void> _register(String dir) async {
    final registry = _registry;
    if (registry == null) return;
    try {
      final file = File(registry);
      final known = await file.exists()
          ? await file.readAsLines()
          : const <String>[];
      if (known.contains(dir)) return;
      await file.parent.create(recursive: true);
      await file.writeAsString('$dir\n', mode: FileMode.append);
    } catch (e) {
      log.warn('generators', 'could not record cache folder $dir: $e');
    }
  }

  static String? _volumeRoot(String dir) {
    try {
      if (PlatformPaths.isRemoteUri(dir) || PlatformPaths.isNetworkPath(dir)) {
        return null;
      }
      if (Platform.isWindows) return _windowsVolumeRoot(dir);
      if (Platform.isLinux) return _linuxVolumeRoot(dir);
      if (Platform.isMacOS) return _macVolumeRoot(dir);
    } catch (e) {
      log.warn('generators', 'volume lookup failed for $dir: $e');
    }

    return null;
  }

  static final _driveLetter = RegExp(r'^([A-Za-z]):(?:[\\/]|$)');

  static String? _windowsVolumeRoot(String dir) {
    var real = dir;
    for (var i = 0; i < 4; i++) {
      final next = _resolveSubst(real);
      if (next == null) break;
      real = next;
    }
    final match = _driveLetter.firstMatch(real);
    if (match == null) return null;
    final letterRoot = '${match.group(1)!.toUpperCase()}:\\';
    final rootPtr = letterRoot.toNativeUtf16();
    try {
      final type = GetDriveType(rootPtr);
      if (type != DRIVE_FIXED && type != DRIVE_REMOVABLE) return null;
    } finally {
      free(rootPtr);
    }
    final pathPtr = real.toNativeUtf16();
    final buffer = wsalloc(MAX_PATH + 1);
    try {
      if (GetVolumePathName(pathPtr, buffer, MAX_PATH + 1) == 0) {
        return letterRoot;
      }

      return buffer.toDartString();
    } finally {
      free(pathPtr);
      free(buffer);
    }
  }

  static String? _resolveSubst(String path) {
    final match = _driveLetter.firstMatch(path);
    if (match == null) return null;
    final device = '${match.group(1)!.toUpperCase()}:'.toNativeUtf16();
    final buffer = wsalloc(1024);
    try {
      if (QueryDosDevice(device, buffer, 1024) == 0) return null;
      final target = buffer.toDartString();
      if (!target.startsWith(r'\??\')) return null;
      final mapped = target.substring(4);
      final rest = path.substring(2).replaceFirst(RegExp(r'^[\\/]+'), '');

      return rest.isEmpty ? mapped : p.join(mapped, rest);
    } finally {
      free(device);
      free(buffer);
    }
  }

  static void _markHidden(String path) {
    final ptr = path.toNativeUtf16();
    try {
      SetFileAttributes(ptr, FILE_ATTRIBUTE_HIDDEN);
    } finally {
      free(ptr);
    }
  }

  static const _skippedLinuxFs = {
    'nfs',
    'nfs4',
    'cifs',
    'smbfs',
    'smb3',
    'sshfs',
    'fuse.sshfs',
    'fuse.rclone',
    '9p',
    'davfs',
    'fuse.davfs2',
    'afs',
    'ceph',
    'glusterfs',
    'tmpfs',
    'devtmpfs',
    'proc',
    'sysfs',
    'overlay',
    'squashfs',
  };

  static List<(String, String)>? _linuxMounts;

  static List<(String, String)> _readLinuxMounts() {
    return _linuxMounts ??= [
      for (final line in File('/proc/self/mounts').readAsLinesSync())
        if (line.split(' ') case [_, final mount, final type, ...])
          (mount.replaceAll(r'\040', ' '), type),
    ];
  }

  static String? _linuxVolumeRoot(String dir) {
    final match = longestMountFor(dir, _readLinuxMounts());
    if (match == null || _skippedLinuxFs.contains(match.$2)) return null;

    return match.$1;
  }

  static (String, String)? longestMountFor(
    String dir,
    List<(String, String)> mounts,
  ) {
    (String, String)? best;
    for (final mount in mounts) {
      final point = mount.$1;
      final inside = point == '/' || dir == point || p.isWithin(point, dir);
      if (!inside) continue;
      if (best == null || point.length > best.$1.length) best = mount;
    }

    return best;
  }

  static List<(String, String)>? _macMounts;

  static String? _macVolumeRoot(String dir) {
    _macMounts ??= [
      for (final line
          in (Process.runSync('mount', const []).stdout as String).split('\n'))
        if (RegExp(r'^\S+ on (.+) \(([^,)]+)(.*)\)$').firstMatch(line)
            case final m?)
          (m.group(1)!, m.group(3)!.contains('local') ? m.group(2)! : 'remote'),
    ];
    final match = longestMountFor(dir, _macMounts!);
    if (match == null || match.$2 == 'remote') return null;

    return match.$1;
  }

  static Iterable<String> _candidateRoots() sync* {
    if (Platform.isWindows) {
      for (var i = 0; i < 26; i++) {
        final root = '${String.fromCharCode(65 + i)}:\\';
        final ptr = root.toNativeUtf16();
        try {
          final type = GetDriveType(ptr);
          if (type == DRIVE_FIXED || type == DRIVE_REMOVABLE) yield root;
        } finally {
          free(ptr);
        }
      }

      return;
    }
    final mounts = Platform.isLinux ? _readLinuxMounts() : (_macMounts ?? []);
    for (final (point, type) in mounts) {
      if (!_skippedLinuxFs.contains(type) && type != 'remote') yield point;
    }
  }
}

typedef _GetuidNative = Uint32 Function();
typedef _GetuidDart = int Function();
typedef _AccessNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _AccessDart = int Function(Pointer<Utf8>, int);
typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);
typedef _StatxNative =
    Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32, Pointer<Uint8>);
typedef _StatxDart = int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>);

class _Posix {
  static const _writeAndSearch = 2 | 1;
  static const _atFdCwd = -100;
  static const _statxUid = 0x8;
  static const _statxBufferSize = 256;
  static const _statxUidOffset = 20;
  static const _ownerOnly = 448;

  static final DynamicLibrary? _libc = Platform.isWindows
      ? null
      : DynamicLibrary.process();

  static bool _has(String name) {
    try {
      return _libc?.providesSymbol(name) ?? false;
    } catch (_) {
      return false;
    }
  }

  static final _GetuidDart? _getuid = _has('getuid')
      ? _libc!.lookupFunction<_GetuidNative, _GetuidDart>('getuid')
      : null;
  static final _AccessDart? _access = _has('access')
      ? _libc!.lookupFunction<_AccessNative, _AccessDart>('access')
      : null;
  static final _ChmodDart? _chmod = _has('chmod')
      ? _libc!.lookupFunction<_ChmodNative, _ChmodDart>('chmod')
      : null;
  static final _StatxDart? _statx = Platform.isLinux && _has('statx')
      ? _libc!.lookupFunction<_StatxNative, _StatxDart>('statx')
      : null;

  static final int? uid = _getuid?.call();

  static bool writable(String path) {
    final access = _access;
    if (access == null) return false;
    final native = path.toNativeUtf8();
    try {
      return access(native, _writeAndSearch) == 0;
    } finally {
      calloc.free(native);
    }
  }

  static bool restrictToOwner(String path) {
    final chmod = _chmod;
    if (chmod == null) return false;
    final native = path.toNativeUtf8();
    try {
      return chmod(native, _ownerOnly) == 0;
    } finally {
      calloc.free(native);
    }
  }

  static int? ownerOf(String path) {
    if (Platform.isLinux) return _linuxOwner(path);
    if (Platform.isMacOS) return _macOwner(path);

    return null;
  }

  static int? _linuxOwner(String path) {
    final statx = _statx;
    if (statx == null) return null;
    final native = path.toNativeUtf8();
    final buffer = calloc<Uint8>(_statxBufferSize);
    try {
      if (statx(_atFdCwd, native, 0, _statxUid, buffer) != 0) return null;

      return (buffer + _statxUidOffset).cast<Uint32>().value;
    } finally {
      calloc.free(native);
      calloc.free(buffer);
    }
  }

  static int? _macOwner(String path) {
    try {
      final result = Process.runSync('stat', ['-f', '%u', path]);
      if (result.exitCode != 0) return null;

      return int.tryParse((result.stdout as String).trim());
    } catch (_) {
      return null;
    }
  }
}
