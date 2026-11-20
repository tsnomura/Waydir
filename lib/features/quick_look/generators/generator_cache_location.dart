import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/platform/platform_paths.dart';

class GeneratorCacheLocation {
  GeneratorCacheLocation._();

  static const folderName = '.waydir-cache';
  static const childName = 'generator_cache';

  static final _dirByRoot = <String, Future<String?>>{};
  static final _rootByDir = <String, String?>{};

  static Future<String> forSource(
    String sourcePath, {
    required String fallback,
  }) async {
    final root = volumeRootOfDirectory(p.dirname(sourcePath));
    if (root == null) return fallback;
    final fallbackRoot = volumeRootOfDirectory(fallback);
    if (fallbackRoot != null && _sameRoot(root, fallbackRoot)) return fallback;
    final dir = await (_dirByRoot[_rootKey(root)] ??= _prepare(root));

    return dir ?? fallback;
  }

  static Future<List<String>> existingDirectories() async {
    final dirs = <String>{};
    for (final pending in _dirByRoot.values) {
      final dir = await pending;
      if (dir != null) dirs.add(dir);
    }
    for (final root in _candidateRoots()) {
      final dir = p.join(root, folderName, childName);
      if (await Directory(dir).exists()) dirs.add(dir);
    }

    return dirs.toList();
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

  static Future<String?> _prepare(String root) async {
    final base = p.join(root, folderName);
    final dir = p.join(base, childName);
    try {
      await Directory(dir).create(recursive: true);
      final probe = File(p.join(dir, '.write-test-$pid'));
      await probe.writeAsString('');
      await probe.delete();
      if (Platform.isWindows) _markHidden(base);

      return dir;
    } catch (e) {
      log.warn('generators', 'cache on $root unavailable, using default: $e');

      return null;
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
