const defaultDiffTimeoutSeconds = 8;
const maxDiffTimeoutSeconds = 60;

/// The external command Quick Look runs to build a side-by-side diff of the
/// two files selected across panes in compare mode.
///
/// `diff -y` truncates (not wraps) lines longer than its `--width`, so the
/// default template asks for a generous width no real text line is likely to
/// exceed — [%WIDTH%] is substituted with a fixed constant, not the live
/// preview pane width, since re-running the command on every resize would
/// make the preview flicker.
class DiffCommandConfig {
  final String cmd;
  final List<String> args;
  final Duration timeout;

  const DiffCommandConfig({
    required this.cmd,
    required this.args,
    required this.timeout,
  });

  static const DiffCommandConfig fallback = DiffCommandConfig(
    cmd: 'diff',
    args: ['-y', '--strip-trailing-cr', '--width=%WIDTH%', '%LEFT%', '%RIGHT%'],
    timeout: Duration(seconds: defaultDiffTimeoutSeconds),
  );

  factory DiffCommandConfig.fromJson(Map<String, dynamic> json) {
    final cmd = json['cmd'] as String?;
    if (cmd == null || cmd.isEmpty) {
      throw const FormatException('compare diff "cmd" is required');
    }
    final args = (json['args'] as List?)?.whereType<String>().toList();
    if (args == null) {
      throw const FormatException(
        'compare diff "args" must be a list of strings',
      );
    }
    final timeoutSeconds =
        (json['timeoutSeconds'] as num?)?.toInt() ?? defaultDiffTimeoutSeconds;

    return DiffCommandConfig(
      cmd: cmd,
      args: args,
      timeout: Duration(
        seconds: timeoutSeconds.clamp(1, maxDiffTimeoutSeconds),
      ),
    );
  }
}
