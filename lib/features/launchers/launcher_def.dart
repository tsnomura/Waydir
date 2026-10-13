enum LauncherContext { open, compare }

class LauncherDef {
  final String id;
  final String name;
  final LauncherContext context;
  final Set<String> extensions;
  final String cmd;
  final List<String> args;
  final bool isDefault;
  final int minFiles;
  final int? maxFiles;

  const LauncherDef({
    required this.id,
    required this.name,
    required this.context,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.isDefault,
    this.minFiles = 1,
    this.maxFiles,
  });

  bool acceptsCount(int count) =>
      count >= minFiles && (maxFiles == null || count <= maxFiles!);

  static const wildcard = '*';

  bool get matchesAll => extensions.isEmpty || extensions.contains(wildcard);

  bool matchesExtension(String extension) =>
      matchesAll || extensions.contains(extension.toLowerCase());

  bool get takesAllFiles => args.any((a) => a.contains('%FILES%'));

  factory LauncherDef.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('launcher "id" is required');
    }
    final cmd = json['cmd'] as String?;
    if (cmd == null || cmd.isEmpty) {
      throw const FormatException('launcher "cmd" is required');
    }
    final args = (json['args'] as List?)?.whereType<String>().toList();
    if (args == null) {
      throw const FormatException('launcher "args" must be a list of strings');
    }
    final context = switch (json['context'] as String?) {
      null || 'open' => LauncherContext.open,
      'compare' => LauncherContext.compare,
      final other => throw FormatException(
        'launcher "context" must be "open" or "compare", got "$other"',
      ),
    };
    final extensions =
        (json['extensions'] as List?)
            ?.whereType<String>()
            .map((e) => e.toLowerCase().replaceFirst(RegExp(r'^\.'), ''))
            .toSet() ??
        <String>{};
    if (context == LauncherContext.open && extensions.isEmpty) {
      throw const FormatException(
        'launcher "extensions" must be a non-empty list for "open" launchers',
      );
    }
    final isDefault = json['default'] == true;
    if (context == LauncherContext.open &&
        isDefault &&
        extensions.contains(wildcard)) {
      throw const FormatException(
        'launcher "default" cannot be used with the "*" extension for "open" '
        'launchers',
      );
    }
    final minFiles = json['minFiles'] ?? 1;
    final maxFiles = json['maxFiles'];
    if (minFiles is! int || minFiles < 1) {
      throw const FormatException('launcher "minFiles" must be at least 1');
    }
    if (maxFiles != null && (maxFiles is! int || maxFiles < minFiles)) {
      throw const FormatException(
        'launcher "maxFiles" must be an integer not less than "minFiles"',
      );
    }

    return LauncherDef(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : id,
      context: context,
      extensions: extensions,
      cmd: cmd,
      args: args,
      isDefault: isDefault,
      minFiles: minFiles,
      maxFiles: maxFiles as int?,
    );
  }
}
