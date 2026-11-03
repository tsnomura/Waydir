import '../../core/archive/archive_path.dart';
import '../../core/platform/platform_paths.dart';
import '../../core/platform/trash_location.dart';
import '../tags/tag_path.dart';

Map<String, dynamic> pluginLocation(String dir) {
  String scheme;
  ArchiveLocation? archive;
  if (PlatformPaths.isSftpUri(dir)) {
    scheme = 'sftp';
  } else if (PlatformPaths.isSmbUri(dir)) {
    scheme = 'smb';
  } else if (isTrashPath(dir)) {
    scheme = 'trash';
  } else if (isTagPath(dir)) {
    scheme = 'tag';
  } else {
    archive = ArchivePath.resolve(dir);
    scheme = archive == null ? 'file' : 'archive';
  }

  return {
    'scheme': scheme,
    'is_local': scheme == 'file',
    if (archive != null) 'archive': archive.archivePath,
    if (archive != null) 'inner': archive.innerPath,
  };
}
