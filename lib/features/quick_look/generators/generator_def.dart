const defaultGeneratorTimeoutSeconds = 8;
const maxGeneratorTimeoutSeconds = 60;

/// How a generator's [GeneratorDef.pageCount]/`%SEEK%`/`%POSITION%` are
/// derived.
enum PagingMode {
  /// Single, fixed preview — no paging.
  none,

  /// [GeneratorDef.pageCount] evenly-spaced samples across a timed source
  /// (e.g. video). `probeCmd` reports the source's duration in seconds,
  /// used to compute `%SEEK%` for each page.
  time,

  /// A source with a real, file-specific unit count (e.g. a PDF's page
  /// count). `probeCmd` reports that count directly — there's no fixed
  /// `pageCount` in config, since it varies per file.
  discrete,
}

class GeneratorDef {
  final String id;
  final Set<String> extensions;
  final String cmd;
  final List<String> args;
  final Duration timeout;
  final String outputExt;
  final PagingMode pagingMode;

  /// Fixed sample count for [PagingMode.time]. Unused otherwise.
  final int pageCount;

  /// Command that prints a plain number to stdout: a duration in seconds
  /// for [PagingMode.time], or a page/unit count for [PagingMode.discrete].
  /// Required by both paging modes.
  final String? probeCmd;
  final List<String> probeArgs;

  /// Regex to extract the number from `probeCmd`'s output when it isn't
  /// already a bare number (e.g. `pdfinfo`/`mutool info` print `Pages: 5`
  /// among other metadata) — the first capture group is used, or the whole
  /// match if the pattern has none. When null, the whole trimmed output is
  /// parsed as a number directly.
  final String? probePattern;

  const GeneratorDef({
    required this.id,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.timeout,
    required this.outputExt,
    this.pagingMode = PagingMode.none,
    this.pageCount = 1,
    this.probeCmd,
    this.probeArgs = const [],
    this.probePattern,
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
    final pagingMode = switch (json['paging'] as String?) {
      'time' => PagingMode.time,
      'discrete' => PagingMode.discrete,
      null => PagingMode.none,
      final other => throw FormatException(
        'generator "paging" must be "time" or "discrete", got "$other"',
      ),
    };
    final pageCount = (json['pageCount'] as num?)?.toInt() ?? 1;
    final probeCmd = json['probeCmd'] as String?;
    final probeArgs =
        (json['probeArgs'] as List?)?.whereType<String>().toList() ?? const [];
    final probePattern = json['probePattern'] as String?;
    if (pagingMode == PagingMode.time && pageCount <= 1) {
      throw const FormatException(
        'generator "pageCount" must be > 1 when "paging" is "time"',
      );
    }
    if (pagingMode != PagingMode.none &&
        (probeCmd == null || probeCmd.isEmpty)) {
      throw const FormatException(
        'generator "probeCmd" is required when "paging" is set',
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
      pagingMode: pagingMode,
      pageCount: pagingMode == PagingMode.time ? pageCount : 1,
      probeCmd: probeCmd,
      probeArgs: probeArgs,
      probePattern: probePattern,
    );
  }
}
