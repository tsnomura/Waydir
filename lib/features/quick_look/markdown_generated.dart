import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../core/models/file_entry.dart';
import '../../i18n/strings.g.dart';
import 'generators/generator_def.dart';
import 'generators/generator_registry.dart';
import 'generators/generator_runner.dart';
import 'markdown_mermaid.dart';

const generatedFenceTag = 'generated_fence';
const _languageAttr = 'language';

const nativeMarkdownImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'svg',
};

class GeneratorFenceBlockSyntax extends md.BlockSyntax {
  const GeneratorFenceBlockSyntax();

  static final _opening = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([\w+.#-]+)\s*$');

  @override
  RegExp get pattern => _opening;

  @override
  bool canParse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content);
    if (match == null) return false;

    return GeneratorRegistry.instance.forFence(match[2]!) != null;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content)!;
    final language = match[2]!.toLowerCase();
    final body = readFenceBody(parser, match[1]!);

    return md.Element.text(generatedFenceTag, body)
      ..attributes[_languageAttr] = language;
  }
}

class GeneratedFenceBuilder extends MarkdownElementBuilder {
  final TextStyle codeStyle;
  final Decoration? codeDecoration;
  final EdgeInsets codePadding;

  GeneratedFenceBuilder({
    required this.codeStyle,
    this.codeDecoration,
    this.codePadding = const EdgeInsets.all(10),
  });

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return GeneratedFence(
      language: element.attributes[_languageAttr] ?? '',
      source: element.textContent,
      codeStyle: codeStyle,
      codeDecoration: codeDecoration,
      codePadding: codePadding,
    );
  }
}

typedef GeneratedOutput = ({GeneratorDef def, String path});

Widget _generatedImage(GeneratedOutput result, Widget Function() fallback) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Image.file(
      File(result.path),
      scale: result.def.imageScale,
      fit: BoxFit.scaleDown,
      errorBuilder: (_, _, _) => fallback(),
    ),
  );
}

String? _readText(GeneratedOutput result) {
  try {
    return result.def.trimText(File(result.path).readAsStringSync());
  } catch (_) {
    return null;
  }
}

class GeneratedFence extends StatefulWidget {
  final String language;
  final String source;
  final TextStyle codeStyle;
  final Decoration? codeDecoration;
  final EdgeInsets codePadding;

  const GeneratedFence({
    super.key,
    required this.language,
    required this.source,
    required this.codeStyle,
    this.codeDecoration,
    this.codePadding = const EdgeInsets.all(10),
  });

  @override
  State<GeneratedFence> createState() => _GeneratedFenceState();
}

class _GeneratedFenceState extends State<GeneratedFence> {
  late Future<GeneratedOutput?> _result;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(GeneratedFence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.language != widget.language) {
      _start();
    }
  }

  void _start() {
    final def = GeneratorRegistry.instance.forFence(widget.language);
    _result = def == null
        ? Future.value(null)
        : GeneratorRunner.previewFence(
            widget.language,
            widget.source,
          ).then((path) => path == null ? null : (def: def, path: path));
  }

  Widget _code(String text, {String? note}) => fencedSource(
    source: text,
    style: widget.codeStyle,
    decoration: widget.codeDecoration,
    padding: widget.codePadding,
    note: note,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GeneratedOutput?>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _code(widget.source);
        }
        final result = snapshot.data;
        if (result == null) {
          final id = GeneratorRegistry.instance.forFence(widget.language)?.id;

          return _code(
            widget.source,
            note: t.quickLook.generatorFenceFailed(id: id ?? widget.language),
          );
        }
        if (result.def.textOutput) {
          return _code(_readText(result) ?? widget.source);
        }

        return _generatedImage(result, () => _code(widget.source));
      },
    );
  }
}

bool wantsGeneratedImage(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (nativeMarkdownImageExtensions.contains(ext)) return false;
  final def = GeneratorRegistry.instance.forExtension(ext);

  return def != null && !def.textOutput;
}

Future<GeneratedOutput?> generateImageFor(File file) async {
  if (!await file.exists()) return null;
  final entry = FileEntry.fromFileSystemEntity(file);
  final def = GeneratorRegistry.instance.forExtension(entry.extension);
  if (def == null || def.textOutput) return null;
  final path = await GeneratorRunner.preview(entry);

  return path == null ? null : (def: def, path: path);
}

Widget generatedImage(GeneratedOutput output) =>
    _generatedImage(output, () => const SizedBox.shrink());
