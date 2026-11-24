import 'dart:io';

import 'package:path/path.dart' as p;

class MsysMounts {
  final String root;
  final List<(String, String)> mounts;

  const MsysMounts({required this.root, this.mounts = const []});

  static final _byRoot = <String, MsysMounts?>{};
  static final _rootByProgram = <String, String?>{};

  static MsysMounts? forShell(String program) {
    final root = _rootByProgram.putIfAbsent(program, () => rootFor(program));
    if (root == null) return null;

    return _byRoot.putIfAbsent(root.toLowerCase(), () => _load(root));
  }

  static String? rootFor(String program) {
    final exe = _locate(program);
    if (exe == null) return null;
    var dir = p.windows.dirname(exe);
    if (p.windows.basename(dir).toLowerCase() == 'bin') {
      dir = p.windows.dirname(dir);
    }
    if (p.windows.basename(dir).toLowerCase() == 'usr') {
      dir = p.windows.dirname(dir);
    }
    final looksLikeRoot =
        Directory(p.windows.join(dir, 'etc')).existsSync() &&
        Directory(p.windows.join(dir, 'usr')).existsSync();

    return looksLikeRoot ? dir : null;
  }

  static String? _locate(String program) {
    if (program.isEmpty) return null;
    if (p.windows.isAbsolute(program)) {
      return File(program).existsSync() ? program : null;
    }
    final name = p.windows.extension(program).isEmpty
        ? '$program.exe'
        : program;
    for (final dir in (Platform.environment['PATH'] ?? '').split(';')) {
      if (dir.trim().isEmpty) continue;
      final candidate = p.windows.join(dir.trim(), name);
      if (File(candidate).existsSync()) return candidate;
    }

    return null;
  }

  static MsysMounts _load(String root) {
    final fstab = File(p.windows.join(root, 'etc', 'fstab'));
    String content = '';
    try {
      if (fstab.existsSync()) content = fstab.readAsStringSync();
    } catch (_) {}

    return MsysMounts(
      root: root,
      mounts: parseFstab(content, temp: Platform.environment['TEMP']),
    );
  }

  static List<(String, String)> parseFstab(String content, {String? temp}) {
    final mounts = <(String, String)>[];
    for (final raw in content.split('\n')) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      final fields = line.split(RegExp(r'\s+'));
      if (fields.length < 3) continue;
      final source = fields[0].replaceAll(r'\040', ' ');
      final point = fields[1].replaceAll(r'\040', ' ');
      final type = fields[2];
      if (!point.startsWith('/') || type == 'cygdrive') continue;
      if (type == 'usertemp') {
        if (temp != null && temp.isNotEmpty) mounts.add((point, temp));
        continue;
      }
      if (source == 'none') continue;
      mounts.add((point, source.replaceAll('/', r'\')));
    }

    return mounts;
  }

  String toWindows(String posix) {
    (String, String)? best;
    for (final mount in mounts) {
      final point = mount.$1;
      final inside =
          posix == point ||
          posix.startsWith(point.endsWith('/') ? point : '$point/');
      if (inside && (best == null || point.length > best.$1.length)) {
        best = mount;
      }
    }
    final String base;
    final String rest;
    if (best != null) {
      base = best.$2;
      rest = posix.substring(best.$1.length);
    } else {
      base = root;
      rest = posix;
    }
    final parts = rest.split('/').where((s) => s.isNotEmpty);

    return p.windows.normalize(p.windows.joinAll([base, ...parts]));
  }
}
