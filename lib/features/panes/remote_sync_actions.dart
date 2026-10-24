import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/fs/sftp_fs.dart';
import '../../core/fs/sftp_session_manager.dart';
import '../../core/platform/platform_paths.dart';

/// The two halves of the "open what the linked machine has open" feature,
/// built entirely on top of an SFTP connection this instance already has
/// into the other machine — the only direction that's reachable when the
/// two machines can't both dial each other (e.g. Windows -> Linux over
/// ssh/sftp works, but nothing reaches back from Linux to Windows).
/// `lib/features/panes/remote_open_request_watcher.dart` is the receiving
/// side on whichever machine gets asked to open a path.
class RemoteSyncActions {
  RemoteSyncActions._();

  static const _activePaneFile = '.config/waydir/pane_dirs/active.txt';
  static const _requestsSubPath = '.config/waydir/remote_open_requests';
  static const _fs = SftpFs();

  /// Reads the directory the linked machine's own active pane is showing
  /// (published by its `PaneDirPublisher`, over the SFTP session already
  /// open for [sftpPath]) and returns it as a location this instance can
  /// open: an `sftp://` URI built from that same session's host/user when
  /// the linked machine reported a bare local path, or the value verbatim
  /// if it was already scheme-qualified. Returns `null` if the linked
  /// machine hasn't published anything yet or the session can't be reached.
  static Future<String?> pullLinkedDirectory(String sftpPath) async {
    final rec = await SftpSessionManager.ensureSession(sftpPath);
    if (rec == null) return null;
    final home = await SftpSessionManager.defaultRemotePath(
      rec.sessionId,
      rec.user,
    );
    final logical = SftpSessionManager.buildLogicalPath(
      host: rec.host,
      port: rec.port,
      user: rec.user,
      remotePath: '$home/$_activePaneFile',
    );
    final String content;
    try {
      final stream = await _fs.openRead(logical);
      content = (await _collect(stream)).trim();
    } catch (_) {
      return null;
    }
    if (content.isEmpty) return null;
    if (PlatformPaths.isRemoteUri(content)) return content;

    return SftpSessionManager.buildLogicalPath(
      host: rec.host,
      port: rec.port,
      user: rec.user,
      remotePath: content,
    );
  }

  /// Asks the linked machine to open [sftpPath] (a path on it, seen through
  /// the SFTP session already open for that path here) as a local
  /// directory. Returns whether the request was delivered.
  static Future<bool> pushDirectoryToLinked(String sftpPath) async {
    final rec = await SftpSessionManager.ensureSession(sftpPath);
    if (rec == null) return false;
    final home = await SftpSessionManager.defaultRemotePath(
      rec.sessionId,
      rec.user,
    );
    final requestsDir = SftpSessionManager.buildLogicalPath(
      host: rec.host,
      port: rec.port,
      user: rec.user,
      remotePath: '$home/$_requestsSubPath',
    );
    final requestFile = SftpSessionManager.buildLogicalPath(
      host: rec.host,
      port: rec.port,
      user: rec.user,
      remotePath:
          '$home/$_requestsSubPath/${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final remotePath = SftpSessionManager.remotePath(sftpPath);
    try {
      await _fs.mkdir(requestsDir, recursive: true);
      await _fs.writeBytes(
        requestFile,
        Uint8List.fromList(utf8.encode(remotePath)),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }

    return utf8.decode(builder.toBytes(), allowMalformed: true);
  }
}
