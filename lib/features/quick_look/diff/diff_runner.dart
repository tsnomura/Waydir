import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../../../core/models/file_entry.dart';
import 'diff_command_config.dart';
import 'diff_command_registry.dart';

/// A generous fixed width, not the live preview pane width — see
/// [DiffCommandConfig]'s doc comment for why this isn't computed dynamically.
const diffCommandWidth = 2000;

enum DiffLineKind {
  /// Present, and identical, on both sides.
  unchanged,

  /// Present only on the right side (`diff -y`'s `>` marker).
  added,

  /// Present only on the left side (`diff -y`'s `<` marker).
  removed,

  /// Present, and different, on both sides (`diff -y`'s `|` marker).
  changed,
}

class DiffLine {
  final DiffLineKind kind;
  final String left;
  final String right;

  const DiffLine({required this.kind, required this.left, required this.right});
}

class TextDiffResult {
  final bool available;
  final List<DiffLine> lines;

  const TextDiffResult({required this.available, required this.lines});

  const TextDiffResult.unavailable() : available = false, lines = const [];
}

/// Runs the configured compare-diff command (`diff -y` by default) and
/// parses its side-by-side output into [DiffLine]s. Every failure mode —
/// missing executable, a real error exit code, a timeout, output that
/// doesn't parse — resolves to [TextDiffResult.unavailable], so the caller
/// can fall back to Quick Look's normal single-file preview.
class DiffRunner {
  DiffRunner._();

  static String cacheKeyFor(FileEntry left, FileEntry right) => [
    left.realPath,
    left.modifiedMs,
    right.realPath,
    right.modifiedMs,
  ].join('|');

  static Future<TextDiffResult> run(FileEntry left, FileEntry right) async {
    final def = DiffCommandRegistry.instance.config;
    final args = _substitute(def.args, left: left, right: right);
    try {
      final process = await Process.start(def.cmd, args);
      // `await process.exitCode` completing doesn't guarantee these streams
      // have finished delivering their data yet — collecting them as
      // futures (rather than firing a callback into a buffer and reading it
      // straight after exitCode) is what actually waits for that.
      final stdoutFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        def.timeout,
        onTimeout: () {
          timedOut = true;
          process.kill();

          return -1;
        },
      );
      final stdoutText = await stdoutFuture;
      await stderrFuture;
      // Standard diff(1) exit codes: 0 = identical, 1 = files differ (both
      // are a successful comparison), 2+ = a real error (bad args, missing
      // file, ...).
      if (timedOut || (exitCode != 0 && exitCode != 1)) {
        log.warn(
          'quick-look',
          'compare diff command "${def.cmd}" failed (exit $exitCode'
              '${timedOut ? ', timed out' : ''}) for '
              '${left.realPath} vs ${right.realPath}',
        );

        return const TextDiffResult.unavailable();
      }

      return TextDiffResult(
        available: true,
        lines: parseDiffOutput(stdoutText),
      );
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'compare diff command "${def.cmd}" errored for '
            '${left.realPath} vs ${right.realPath}',
        error: error,
        stack: stack,
      );

      return const TextDiffResult.unavailable();
    }
  }

  static List<String> _substitute(
    List<String> args, {
    required FileEntry left,
    required FileEntry right,
  }) {
    return args
        .map(
          (arg) => arg
              .replaceAll('%LEFT%', left.realPath)
              .replaceAll('%RIGHT%', right.realPath)
              .replaceAll('%WIDTH%', diffCommandWidth.toString()),
        )
        .toList();
  }
}

/// Parses `diff -y`-style side-by-side output into [DiffLine]s. Exposed
/// separately from [DiffRunner.run] so it can be unit-tested against fixed
/// sample output without spawning a real process.
List<DiffLine> parseDiffOutput(String output) {
  final rawLines = output.split('\n');
  if (rawLines.isNotEmpty && rawLines.last.isEmpty) rawLines.removeLast();

  return rawLines.map(parseDiffLine).toList();
}

/// `diff -y` right-pads each side with tab characters up to a column
/// boundary and separates them with a lone `<`/`>`/`|` token (also
/// tab-delimited) when a line was removed, added or changed — nothing at all
/// when it's unchanged. Splitting on tab finds the marker (a token that
/// trims to exactly one of those three characters) regardless of how much
/// padding surrounds it, and — since diff's own column width has nothing to
/// do with how wide Quick Look's two panes actually render — gives the real
/// left/right content directly, discarding the padding entirely rather than
/// trying to preserve diff's column alignment on screen.
///
/// The one asymmetry: a `<` (left-only) line has no right-side field at
/// all — the last tab-split field *is* the marker itself — so the right
/// side is forced empty rather than read from `fields.last`.
DiffLine parseDiffLine(String raw) {
  final fields = raw.split('\t');
  var kind = DiffLineKind.unchanged;
  for (final field in fields) {
    final trimmed = field.trim();
    if (trimmed == '|') {
      kind = DiffLineKind.changed;
      break;
    }
    if (trimmed == '<') {
      kind = DiffLineKind.removed;
      break;
    }
    if (trimmed == '>') {
      kind = DiffLineKind.added;
      break;
    }
  }
  final left = fields.first;
  final right = kind == DiffLineKind.removed
      ? ''
      : (fields.length > 1 ? fields.last : fields.first);

  return DiffLine(kind: kind, left: left, right: right);
}
