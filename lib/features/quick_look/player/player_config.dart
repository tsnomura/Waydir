class PlayerConfig {
  final String cmd;
  final List<String> args;

  const PlayerConfig({required this.cmd, required this.args});

  factory PlayerConfig.fromJson(Map<String, dynamic> json) {
    final cmd = json['cmd'] as String?;
    if (cmd == null || cmd.isEmpty) {
      throw const FormatException('player "cmd" is required');
    }
    final args = (json['args'] as List?)?.whereType<String>().toList();
    if (args == null) {
      throw const FormatException('player "args" must be a list of strings');
    }

    return PlayerConfig(cmd: cmd, args: args);
  }
}
