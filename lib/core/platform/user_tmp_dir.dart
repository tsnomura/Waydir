import 'dart:io';

import 'package:path/path.dart' as p;

import '../logging/app_logger.dart';

class UserTmpDir {
  UserTmpDir._();

  static Future<String>? _uid;

  static Future<String?> path() async {
    if (Platform.isWindows) {
      return p.join(Directory.systemTemp.path, 'waydir');
    }
    if (!Platform.isLinux) return null;
    final uid = await (_uid ??= _readUid());
    if (uid.isEmpty) return null;

    return '/tmp/waydir-$uid';
  }

  static Future<bool> ensure(String path) async {
    if (Platform.isWindows) {
      try {
        await Directory(path).create(recursive: true);

        return true;
      } catch (e, st) {
        log.warn('platform', 'failed to create $path', error: e, stack: st);

        return false;
      }
    }
    final uid = await (_uid ??= _readUid());
    if (uid.isEmpty) return false;
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await Directory(path).create();
      }
      final stat = await Process.run(
        'stat',
        ['-c', '%u %f', '--', path],
        environment: const {'LC_ALL': 'C'},
      );
      if (stat.exitCode != 0) return false;
      final fields = (stat.stdout as String).trim().split(' ');
      if (fields.length != 2 || fields[0] != uid) return false;
      final mode = int.tryParse(fields[1], radix: 16);
      if (mode == null || mode & 0xF000 != 0x4000) return false;
      if (mode & 0x3F != 0) {
        final chmod = await Process.run('chmod', ['700', '--', path]);
        if (chmod.exitCode != 0) return false;
      }

      return true;
    } catch (e, st) {
      log.warn('platform', 'failed to prepare $path', error: e, stack: st);

      return false;
    }
  }

  static Future<String> _readUid() async {
    try {
      final r = await Process.run('id', ['-u']);
      if (r.exitCode == 0) return (r.stdout as String).trim();
    } catch (e, st) {
      log.warn('platform', 'failed to read process uid', error: e, stack: st);
    }

    return '';
  }
}
