import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../core/platform/app_dirs.dart';
import '../../i18n/strings.g.dart';
import '../../ui/theme/app_theme.dart';

const mermaidTag = 'mermaid';
const _rasterScale = 2.0;
const _renderTimeout = Duration(seconds: 15);

class MermaidBlockSyntax extends md.BlockSyntax {
  const MermaidBlockSyntax();

  static final _opening = RegExp(
    r'^ {0,3}(`{3,}|~{3,})\s*mermaid\s*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _opening;

  @override
  md.Node parse(md.BlockParser parser) {
    final fence = _opening.firstMatch(parser.current.content)![1]!;

    return md.Element.text(mermaidTag, readFenceBody(parser, fence));
  }
}

String readFenceBody(md.BlockParser parser, String fence) {
  final closing = RegExp(
    '^ {0,3}${RegExp.escape(fence[0])}{${fence.length},}\\s*\$',
  );
  parser.advance();
  final lines = <String>[];
  while (!parser.isDone) {
    final line = parser.current.content;
    parser.advance();
    if (closing.hasMatch(line)) break;
    lines.add(line);
  }

  return lines.join('\n');
}

Widget fencedSource({
  required String source,
  required TextStyle style,
  Decoration? decoration,
  EdgeInsets padding = const EdgeInsets.all(10),
  String? note,
}) {
  return Container(
    width: double.infinity,
    decoration: decoration,
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(source, style: style),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: style.copyWith(color: AppColors.fgSubtle)),
        ],
      ],
    ),
  );
}

sealed class MermaidResult {
  const MermaidResult();
}

class MermaidImage extends MermaidResult {
  final String path;

  const MermaidImage(this.path);
}

class MermaidMissingTool extends MermaidResult {
  const MermaidMissingTool();
}

class MermaidFailure extends MermaidResult {
  final String message;

  const MermaidFailure(this.message);
}

class MermaidRenderer {
  static const executableName = 'merman-cli';
  static const overrideEnv = 'WAYDIR_MERMAN_CLI';

  static MermaidRenderer instance = MermaidRenderer();

  final Future<String?> Function() locate;
  final Future<String> Function() cacheDir;
  final Map<String, Future<MermaidResult>> _inFlight = {};

  MermaidRenderer({
    Future<String?> Function()? locate,
    Future<String> Function()? cacheDir,
  }) : locate = locate ?? locateMermanCli,
       cacheDir = cacheDir ?? AppDirs.generatorCache;

  Future<MermaidResult> render(String source, {required bool dark}) {
    final theme = dark ? 'dark' : 'default';
    final key = sha256
        .convert(utf8.encode('merman|$theme|$_rasterScale|$source'))
        .toString();

    return _inFlight[key] ??= _render(source, theme, key).then((result) {
      if (result is! MermaidImage) _inFlight.remove(key);

      return result;
    });
  }

  Future<MermaidResult> _render(String source, String theme, String key) async {
    final dir = await cacheDir();
    final out = p.join(dir, 'mermaid-$key.png');
    if (await File(out).exists()) return MermaidImage(out);

    final exe = await locate();
    if (exe == null) return const MermaidMissingTool();

    final Process process;
    try {
      process = await Process.start(exe, [
        'render',
        '-',
        '--format',
        'png',
        '--theme',
        theme,
        '--background',
        'transparent',
        '--scale',
        '$_rasterScale',
        '--output',
        '-',
      ]);
    } on ProcessException catch (e) {
      return MermaidFailure(e.message);
    }

    final stdoutBytes = BytesBuilder(copy: false);
    final stderrText = StringBuffer();
    final stdoutDone = process.stdout.forEach(stdoutBytes.add);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach(stderrText.write);
    process.stdin.add(utf8.encode(source));
    await process.stdin.close();

    final int code;
    try {
      code = await process.exitCode.timeout(_renderTimeout);
    } on TimeoutException {
      process.kill();

      return MermaidFailure('timed out after ${_renderTimeout.inSeconds}s');
    }
    await Future.wait([stdoutDone, stderrDone]);

    final bytes = stdoutBytes.takeBytes();
    if (code != 0 || bytes.isEmpty) {
      final message = stderrText.toString().trim();

      return MermaidFailure(message.isEmpty ? 'exit code $code' : message);
    }

    final tmp = File(p.join(dir, 'tmp-mermaid-$key.png'));
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(out);

    return MermaidImage(out);
  }
}

Future<String?> locateMermanCli() async {
  final env = Platform.environment;
  final override = env[MermaidRenderer.overrideEnv];
  if (override != null && override.isNotEmpty) {
    return File(override).existsSync() ? override : null;
  }
  final name = Platform.isWindows
      ? '${MermaidRenderer.executableName}.exe'
      : MermaidRenderer.executableName;
  final home = env['HOME'] ?? env['USERPROFILE'];
  final dirs = [
    ...?env['PATH']?.split(Platform.isWindows ? ';' : ':'),
    if (home != null) ...[
      p.join(home, 'bin'),
      p.join(home, '.local', 'bin'),
      p.join(home, '.cargo', 'bin'),
    ],
  ];
  for (final dir in dirs) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, name);
    if (File(candidate).existsSync()) return candidate;
  }

  return null;
}

class MermaidElementBuilder extends MarkdownElementBuilder {
  final TextStyle codeStyle;
  final Decoration? codeDecoration;
  final EdgeInsets codePadding;

  MermaidElementBuilder({
    required this.codeStyle,
    this.codeDecoration,
    this.codePadding = const EdgeInsets.all(10),
  });

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return MermaidDiagram(
      source: element.textContent,
      codeStyle: codeStyle,
      codeDecoration: codeDecoration,
      codePadding: codePadding,
    );
  }
}

class MermaidDiagram extends StatefulWidget {
  final String source;
  final TextStyle codeStyle;
  final Decoration? codeDecoration;
  final EdgeInsets codePadding;

  const MermaidDiagram({
    super.key,
    required this.source,
    required this.codeStyle,
    this.codeDecoration,
    this.codePadding = const EdgeInsets.all(10),
  });

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  late Future<MermaidResult> _result;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _start();
  }

  void _start() {
    _result = MermaidRenderer.instance.render(
      widget.source,
      dark: AppColors.brightness == Brightness.dark,
    );
  }

  Widget _source({String? note}) => fencedSource(
    source: widget.source,
    style: widget.codeStyle,
    decoration: widget.codeDecoration,
    padding: widget.codePadding,
    note: note,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MermaidResult>(
      future: _result,
      builder: (context, snapshot) {
        return switch (snapshot.data) {
          null => _source(),
          MermaidImage(:final path) => Align(
            alignment: Alignment.centerLeft,
            child: Image.file(
              File(path),
              scale: _rasterScale,
              fit: BoxFit.scaleDown,
              errorBuilder: (_, _, _) => _source(),
            ),
          ),
          MermaidMissingTool() => _source(note: t.quickLook.mermaidMissing),
          MermaidFailure(:final message) => _source(
            note: t.quickLook.mermaidFailed(error: message),
          ),
        };
      },
    );
  }
}
