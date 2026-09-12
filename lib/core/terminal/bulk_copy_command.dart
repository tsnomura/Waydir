import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/locations/location_uri.dart';
import '../platform/platform_paths.dart';

enum BulkCopyTool { robocopy, rsync, scp }

/// robocopy/rsync for local (or network-drive) paths on either side, scp
/// when either side is an `sftp://` connection — neither robocopy nor rsync
/// understands Waydir's own URI scheme, and scp is the natural fit for
/// actually talking to a remote SSH host.
BulkCopyTool bulkCopyToolFor({required bool involvesSftp}) {
  if (involvesSftp) return BulkCopyTool.scp;

  return Platform.isWindows ? BulkCopyTool.robocopy : BulkCopyTool.rsync;
}

String bulkCopyToolName(BulkCopyTool tool) => switch (tool) {
  BulkCopyTool.robocopy => 'robocopy',
  BulkCopyTool.rsync => 'rsync',
  BulkCopyTool.scp => 'scp',
};

class BulkCopyOption {
  final String label;
  final String flag;
  final bool defaultOn;

  const BulkCopyOption({
    required this.label,
    required this.flag,
    this.defaultOn = false,
  });
}

const robocopyOptions = [
  BulkCopyOption(
    label: 'Recurse into subfolders, including empty ones',
    flag: '/E',
    defaultOn: true,
  ),
  BulkCopyOption(
    label: 'Multi-threaded (8 threads)',
    flag: '/MT:8',
    defaultOn: true,
  ),
  BulkCopyOption(
    label: 'Restartable mode (resume after a network drop)',
    flag: '/Z',
    defaultOn: true,
  ),
  BulkCopyOption(
    label: 'Mirror (delete extra files at the destination)',
    flag: '/MIR',
  ),
];

const rsyncOptions = [
  BulkCopyOption(
    label: 'Archive mode (recursive, preserve attributes)',
    flag: '-a',
    defaultOn: true,
  ),
  BulkCopyOption(
    label: 'Compress data during transfer',
    flag: '-z',
    defaultOn: true,
  ),
  BulkCopyOption(label: 'Show progress', flag: '--progress', defaultOn: true),
  BulkCopyOption(
    label: 'Delete extra files at the destination',
    flag: '--delete',
  ),
];

const scpOptions = [
  BulkCopyOption(label: 'Recurse into subfolders', flag: '-r', defaultOn: true),
  BulkCopyOption(
    label: 'Compress data during transfer',
    flag: '-C',
    defaultOn: true,
  ),
];

List<BulkCopyOption> bulkCopyOptionsFor(BulkCopyTool tool) => switch (tool) {
  BulkCopyTool.robocopy => robocopyOptions,
  BulkCopyTool.rsync => rsyncOptions,
  BulkCopyTool.scp => scpOptions,
};

class BulkCopySource {
  /// A local/network path, or an `sftp://` URI.
  final String path;
  final bool isFolder;

  const BulkCopySource({required this.path, required this.isFolder});
}

/// Builds the command line to copy [sources] into [destinationDir], with
/// [flags] (a subset of [bulkCopyOptionsFor]'s flags for [tool], in that
/// list's order).
///
/// rsync and scp both accept any number of source arguments in one call,
/// copying each into [destinationDir] (a directory source becomes a
/// same-named subfolder there). robocopy only takes one source directory
/// per invocation, so multiple sources become multiple `robocopy` calls
/// chained with `&&`: one per selected folder (into a same-named subfolder
/// of [destinationDir]), plus one more per group of selected files that
/// share a parent directory (robocopy's own file-filter arguments list them
/// by name after source/destination — each such call's destination is
/// [destinationDir] directly, since loose files don't get a subfolder of
/// their own).
String buildBulkCopyCommand({
  required BulkCopyTool tool,
  required List<BulkCopySource> sources,
  required String destinationDir,
  required List<String> flags,
}) {
  if (sources.isEmpty) return '';
  switch (tool) {
    case BulkCopyTool.scp:
      return _buildScpCommand(sources, destinationDir, flags);
    case BulkCopyTool.rsync:
      return _buildRsyncCommand(sources, destinationDir, flags);
    case BulkCopyTool.robocopy:
      return _buildRobocopyCommand(sources, destinationDir, flags);
  }
}

String _buildRsyncCommand(
  List<BulkCopySource> sources,
  String destinationDir,
  List<String> flags,
) {
  return [
    'rsync',
    ...flags,
    ...sources.map((s) => _posixQuote(s.path)),
    _posixQuote(destinationDir),
  ].join(' ');
}

String _buildRobocopyCommand(
  List<BulkCopySource> sources,
  String destinationDir,
  List<String> flags,
) {
  final commands = <String>[];
  final filesByParent = <String, List<String>>{};
  for (final source in sources) {
    if (source.isFolder) {
      final finalDest = p.join(destinationDir, p.basename(source.path));
      commands.add(
        [
          'robocopy',
          _windowsQuote(source.path),
          _windowsQuote(finalDest),
          ...flags,
        ].join(' '),
      );
    } else {
      (filesByParent[p.dirname(source.path)] ??= []).add(
        p.basename(source.path),
      );
    }
  }
  filesByParent.forEach((parent, names) {
    commands.add(
      [
        'robocopy',
        _windowsQuote(parent),
        _windowsQuote(destinationDir),
        ...names.map(_windowsQuote),
        ...flags,
      ].join(' '),
    );
  });

  return commands.join(' && ');
}

String _buildScpCommand(
  List<BulkCopySource> sources,
  String destinationDir,
  List<String> flags,
) {
  final port = _scpPort(sources, destinationDir);
  final portFlags = (port != null && port != 22) ? ['-P', '$port'] : const [];

  return [
    'scp',
    ...flags,
    ...portFlags,
    ...sources.map((s) => _scpSpec(s.path)),
    _scpSpec(destinationDir),
  ].join(' ');
}

int? _scpPort(List<BulkCopySource> sources, String destinationDir) {
  for (final source in sources) {
    if (PlatformPaths.isSftpUri(source.path)) {
      final port = LocationUri.parse(source.path).port;
      if (port != null) return port;
    }
  }
  if (PlatformPaths.isSftpUri(destinationDir)) {
    return LocationUri.parse(destinationDir).port;
  }

  return null;
}

/// A local path quoted as-is, or `user@host:remotePath` for an `sftp://`
/// entry — the spec form scp expects for its remote side.
String _scpSpec(String path) {
  if (!PlatformPaths.isSftpUri(path)) {
    return Platform.isWindows ? _windowsQuote(path) : _posixQuote(path);
  }
  final uri = LocationUri.parse(path);
  final user = (uri.username == null || uri.username!.isEmpty)
      ? ''
      : '${uri.username}@';
  // LocationUri.path never includes the leading slash (it's split off of
  // the URI's authority component) — put it back, since without it scp/ssh
  // would treat the remote path as relative to the login's home directory
  // instead of absolute.
  final spec = '$user${uri.host}:/${uri.path ?? ''}';

  return Platform.isWindows ? _windowsQuote(spec) : _posixQuote(spec);
}

String _windowsQuote(String value) => '"${value.replaceAll('"', '""')}"';

final _posixNeedsQuoting = RegExp(r'''[\s'"`$\\|&;()<>*?!\[\]{}]''');

String _posixQuote(String value) {
  if (value.isEmpty) return "''";
  if (!_posixNeedsQuoting.hasMatch(value)) return value;

  return "'${value.replaceAll("'", r"'\''")}'";
}
