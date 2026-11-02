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

  fixed,
}

class GeneratorDef {
  final String id;
  final Set<String> extensions;
  final String cmd;
  final List<String> args;
  final Duration timeout;
  final String outputExt;
  final PagingMode pagingMode;

  /// Writes the command's stdout to `%OUTPUT%` instead of expecting the
  /// command to write the file itself — for tools that only print their
  /// result (e.g. `7z l`, or an image converter that streams PNG to stdout).
  final bool captureStdout;

  /// For text output: a regex for the first line to show. Everything above
  /// it (e.g. a tool's banner) is dropped; no match shows the whole text.
  final String? textFrom;

  /// Overrides [args] for the file grid's thumbnail only — Quick Look always
  /// uses [args]. Null (the default) means the grid reuses page 0 of [args]
  /// verbatim, same cache entry and all. Always a single static image: the
  /// grid never pages, regardless of [pagingMode]. For a generator whose
  /// full preview is too dense to read shrunk down to a tile (e.g. a type
  /// specimen's sample paragraph plus its family name), this renders
  /// something simpler instead — it doesn't have to be the same kind of
  /// image as [args] at all.
  final List<String>? thumbnailArgs;

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

  /// Markdown fenced-code languages (lowercase) this generator renders in the
  /// Markdown preview, e.g. `["dot", "graphviz"]` for ` ```dot ` blocks. The
  /// block's body is written to a temp file with the first of [extensions].
  final Set<String> fences;

  /// Device-pixel ratio the generated image was rendered at, so a `2` image
  /// is shown at half its pixel size in the Markdown preview (crisp on HiDPI).
  final double imageScale;

  /// What `%THEME%` expands to for the app's `dark` and `light` themes when
  /// a tool uses other names (e.g. `{"light": "default"}`).
  final Map<String, String> themeNames;

  const GeneratorDef({
    required this.id,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.timeout,
    required this.outputExt,
    this.pagingMode = PagingMode.none,
    this.captureStdout = false,
    this.textFrom,
    this.pageCount = 1,
    this.probeCmd,
    this.probeArgs = const [],
    this.probePattern,
    this.thumbnailArgs,
    this.fences = const {},
    this.imageScale = 1.0,
    this.themeNames = const {},
  });

  bool get usesTheme =>
      args.any((a) => a.contains('%THEME%')) ||
      (thumbnailArgs?.any((a) => a.contains('%THEME%')) ?? false);

  String themeArg({required bool dark}) {
    final name = dark ? 'dark' : 'light';

    return themeNames[name] ?? name;
  }

  /// `outputExt: "txt"` makes the generator's output text, shown in Quick
  /// Look's read-only text view rather than as an image.
  bool get textOutput => outputExt.toLowerCase() == 'txt';

  String trimText(String text) {
    final pattern = textFrom;
    if (pattern == null || pattern.isEmpty) return text;
    final RegExp re;
    try {
      re = RegExp(pattern);
    } on FormatException {
      return text;
    }
    var start = 0;
    while (start < text.length) {
      final newline = text.indexOf('\n', start);
      final end = newline < 0 ? text.length : newline;
      var line = text.substring(start, end);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (re.hasMatch(line)) return text.substring(start);
      if (newline < 0) break;
      start = newline + 1;
    }

    return text;
  }

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
      'fixed' => PagingMode.fixed,
      null => PagingMode.none,
      final other => throw FormatException(
        'generator "paging" must be "time", "discrete" or "fixed", got '
        '"$other"',
      ),
    };
    final pageCount = (json['pageCount'] as num?)?.toInt() ?? 1;
    final probeCmd = json['probeCmd'] as String?;
    final probeArgs =
        (json['probeArgs'] as List?)?.whereType<String>().toList() ?? const [];
    final probePattern = json['probePattern'] as String?;
    final thumbnailArgs = (json['thumbnailArgs'] as List?)
        ?.whereType<String>()
        .toList();
    final fences =
        (json['fences'] as List?)
            ?.whereType<String>()
            .map((e) => e.toLowerCase())
            .toSet() ??
        const <String>{};
    final imageScale = ((json['imageScale'] as num?)?.toDouble() ?? 1.0).clamp(
      0.25,
      8.0,
    );
    final themeNames = <String, String>{
      for (final e in ((json['themeNames'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
    final fixedCount =
        pagingMode == PagingMode.time || pagingMode == PagingMode.fixed;
    if (fixedCount && pageCount <= 1) {
      throw const FormatException(
        'generator "pageCount" must be > 1 when "paging" is "time" or "fixed"',
      );
    }
    if ((pagingMode == PagingMode.time || pagingMode == PagingMode.discrete) &&
        (probeCmd == null || probeCmd.isEmpty)) {
      throw const FormatException(
        'generator "probeCmd" is required when "paging" is "time" or '
        '"discrete"',
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
      captureStdout: json['stdout'] == true,
      textFrom: json['textFrom'] as String?,
      pageCount: fixedCount ? pageCount : 1,
      probeCmd: probeCmd,
      probeArgs: probeArgs,
      probePattern: probePattern,
      thumbnailArgs: thumbnailArgs,
      fences: fences,
      imageScale: imageScale,
      themeNames: themeNames,
    );
  }
}
