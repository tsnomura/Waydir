const defaultGeneratorTimeoutSeconds = 8;
const maxGeneratorTimeoutSeconds = 60;

class GeneratorDef {
  final String id;
  final Set<String> extensions;
  final String cmd;
  final List<String> args;
  final Duration timeout;
  final String outputExt;

  /// Number of evenly-spaced positions across the file this generator can
  /// render, for paging through a multi-page/timed source (e.g. 10 for a
  /// video sampled every 10% of its duration, from 0% up to but excluding
  /// 100% — decoders can't extract a frame at the exact end of a file). 1
  /// means a single, fixed preview — the common case.
  final int pageCount;

  /// Command that prints the source's duration in seconds (a plain number,
  /// e.g. `ffprobe`'s `-show_entries format=duration`) to stdout. Required
  /// when [pageCount] > 1, since %SEEK% is computed from it.
  final String? probeCmd;
  final List<String> probeArgs;

  const GeneratorDef({
    required this.id,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.timeout,
    required this.outputExt,
    this.pageCount = 1,
    this.probeCmd,
    this.probeArgs = const [],
  });

  factory GeneratorDef.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('generator "id" is required');
    }
    final cmd = json['cmd'] as String?;
    if (cmd == null || cmd.isEmpty) {
      throw const FormatException('generator "cmd" is required');
    }
    final extensions = (json['extensions'] as List?)
        ?.whereType<String>()
        .map((e) => e.toLowerCase())
        .toSet();
    if (extensions == null || extensions.isEmpty) {
      throw const FormatException(
        'generator "extensions" must be a non-empty list of strings',
      );
    }
    final args = (json['args'] as List?)?.whereType<String>().toList();
    if (args == null) {
      throw const FormatException('generator "args" must be a list of strings');
    }
    final timeoutSeconds =
        (json['timeoutSeconds'] as num?)?.toInt() ??
        defaultGeneratorTimeoutSeconds;
    final outputExt = (json['outputExt'] as String?) ?? 'png';
    final pageCount = (json['pageCount'] as num?)?.toInt() ?? 1;
    final probeCmd = json['probeCmd'] as String?;
    final probeArgs =
        (json['probeArgs'] as List?)?.whereType<String>().toList() ?? const [];
    if (pageCount > 1 && (probeCmd == null || probeCmd.isEmpty)) {
      throw const FormatException(
        'generator "probeCmd" is required when "pageCount" > 1',
      );
    }

    return GeneratorDef(
      id: id,
      extensions: extensions,
      cmd: cmd,
      args: args,
      timeout: Duration(
        seconds: timeoutSeconds.clamp(1, maxGeneratorTimeoutSeconds),
      ),
      outputExt: outputExt,
      pageCount: pageCount < 1 ? 1 : pageCount,
      probeCmd: probeCmd,
      probeArgs: probeArgs,
    );
  }
}
