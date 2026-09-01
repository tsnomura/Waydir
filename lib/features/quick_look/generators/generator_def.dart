const defaultGeneratorTimeoutSeconds = 8;
const maxGeneratorTimeoutSeconds = 60;

class GeneratorDef {
  final String id;
  final Set<String> extensions;
  final String cmd;
  final List<String> args;
  final Duration timeout;
  final String outputExt;

  const GeneratorDef({
    required this.id,
    required this.extensions,
    required this.cmd,
    required this.args,
    required this.timeout,
    required this.outputExt,
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

    return GeneratorDef(
      id: id,
      extensions: extensions,
      cmd: cmd,
      args: args,
      timeout: Duration(
        seconds: timeoutSeconds.clamp(1, maxGeneratorTimeoutSeconds),
      ),
      outputExt: outputExt,
    );
  }
}
