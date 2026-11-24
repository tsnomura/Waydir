import 'package:flutter/widgets.dart';

import '../../core/terminal/pty_session.dart';
import '../../core/terminal/terminal_paths.dart';

class TerminalTab {
  final int id;
  int originPane;
  final PtySession session;
  final FocusNode focusNode;
  final String cwd;
  final TerminalPathStyle pathStyle;
  final String shellProgram;
  String label;

  TerminalTab({
    required this.id,
    required this.originPane,
    required this.session,
    required this.focusNode,
    required this.cwd,
    this.pathStyle = TerminalPathStyle.native,
    this.shellProgram = '',
    required this.label,
  });

  void dispose() {
    session.dispose();
    focusNode.dispose();
  }
}
