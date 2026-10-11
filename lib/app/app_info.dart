import 'package:package_info_plus/package_info_plus.dart';
import 'package:signals/signals.dart';

class AppInfo {
  static const String repository = 'Waydir/Waydir';
  static const String homepage = 'https://github.com/Waydir/Waydir';
  static const String license = 'MIT';
  static const String iconAsset = 'assets/app_icon.png';

  static const String personalRepository = 'tsnomura/Waydir';
  static const String personalHomepage = 'https://github.com/tsnomura/Waydir';
  static const String personalVersion = String.fromEnvironment(
    'WAYDIR_PERSONAL_VERSION',
  );
  static const String personalBranch = String.fromEnvironment(
    'WAYDIR_PERSONAL_BRANCH',
  );
  static const String personalCommit = String.fromEnvironment(
    'WAYDIR_PERSONAL_COMMIT',
  );
  static const String personalBuildDate = String.fromEnvironment(
    'WAYDIR_PERSONAL_BUILD_DATE',
  );

  static String? get personalCommitUrl => personalCommit.isEmpty
      ? null
      : '$personalHomepage/commit/$personalCommit';

  static final version = signal<String>('…');
  static final Computed<String> versionLabel = computed(
    () => 'v${version.value}',
  );

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    version.value = info.version;
  }

  const AppInfo._();
}
