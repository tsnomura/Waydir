import '../fs/fs_worker_pool.dart';

typedef ArchivePasswordPrompt =
    Future<String?> Function(String archivePath, {required bool retry});

class ArchivePasswords {
  ArchivePasswords._();

  static ArchivePasswordPrompt? prompt;

  static Future<Map<String, String>?> collect(
    Iterable<String> archivePaths,
  ) async {
    final out = <String, String>{};
    for (final archive in archivePaths.toSet()) {
      if (!await FsWorkerPool.instance.archiveIsEncrypted(archive)) continue;
      final ask = prompt;
      if (ask == null) return null;
      var retry = false;
      while (true) {
        final password = await ask(archive, retry: retry);
        if (password == null) return null;
        if (await FsWorkerPool.instance.verifyArchivePassword(
          archive,
          password,
        )) {
          out[archive] = password;
          break;
        }
        retry = true;
      }
    }

    return out;
  }
}
