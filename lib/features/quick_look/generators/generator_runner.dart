import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/platform/app_dirs.dart';
import 'generator_def.dart';
import 'generator_registry.dart';

/// Runs the generator matching [entry]'s extension, if any, and returns the
/// path to a cached preview image. Returns null when there is no matching
/// generator, or the command failed, timed out, or produced nothing — the
/// caller falls back to the default file icon in every one of those cases.
class GeneratorRunner {
  GeneratorRunner._();

  static const _stderrTailLimit = 4096;

  // Probes are cheap but not free; memoize per file+generator for the
  // lifetime of the app so paging back and forth doesn't re-probe.
  static final _probeCache = <String, Future<double?>>{};

  /// The number of pages [entry]'s matched generator offers: the fixed
  /// [GeneratorDef.pageCount] for [PagingMode.time], the file's own probed
  /// count for [PagingMode.discrete], or 1 for anything else (including no
  /// matching generator at all).
  static Future<int> resolvePageCount(FileEntry entry) async {
    final def = GeneratorRegistry.instance.forExtension(entry.extension);
    if (def == null) return 1;
    if (def.pagingMode != PagingMode.discrete) return def.pageCount;
    final count = await _probeNumber(entry, def);
    if (count == null) return 1;

    return count.round().clamp(1, 100000);
  }

  static Future<String?> preview(FileEntry entry, {int position = 0}) async {
    final def = GeneratorRegistry.instance.forExtension(entry.extension);
    if (def == null) return null;

    var page = position < 0 ? 0 : position;
    var seek = '00:00:00.000';
    if (def.pagingMode == PagingMode.time) {
      page = page.clamp(0, def.pageCount - 1);
      final duration = await _probeNumber(entry, def);
      if (duration == null) return null;
      // Never seek to the exact end of the file — ffmpeg (and most decoders)
      // can't extract a frame past the last one, so pageCount samples split
      // [0, duration) rather than [0, duration].
      seek = _formatSeek(duration * page / def.pageCount);
    }

    final cacheDir = await AppDirs.generatorCache();
    final cachePath = p.join(
      cacheDir,
      '${_cacheKey(entry, def, page)}.${def.outputExt}',
    );
    if (await File(cachePath).exists()) return cachePath;

    // Must keep the real output extension at the end (not appended after
    // it) — tools like ffmpeg infer the output format/muxer from the
    // filename extension, so "*.png.tmp-123" fails while "tmp-123.png"
    // works.
    final tmpPath = p.join(
      cacheDir,
      'tmp-${DateTime.now().microsecondsSinceEpoch}.${def.outputExt}',
    );
    final args = _substitute(
      def.args,
      entry: entry,
      output: tmpPath,
      cacheDir: cacheDir,
      seek: seek,
      position: page,
    );

    try {
      final result = await _run(def.cmd, args, def.timeout);
      if (result.timedOut || result.exitCode != 0) {
        log.warn(
          'quick-look',
          'generator "${def.id}" failed (exit ${result.exitCode}'
              '${result.timedOut ? ', timed out' : ''}) for '
              '${entry.realPath}: ${result.stderrTail}',
        );
        await _tryDelete(tmpPath);

        return null;
      }
      final tmpFile = File(tmpPath);
      if (!await tmpFile.exists()) return null;
      await tmpFile.rename(cachePath);

      return cachePath;
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'generator "${def.id}" errored for ${entry.realPath}',
        error: error,
        stack: stack,
      );
      await _tryDelete(tmpPath);

      return null;
    }
  }

  /// Runs [def.probeCmd] and returns a duration in seconds ([PagingMode.time])
  /// or a page/unit count ([PagingMode.discrete]) — [def.probePattern]
  /// extracts it from the output when it isn't already a bare number.
  static Future<double?> _probeNumber(FileEntry entry, GeneratorDef def) {
    final key = [
      entry.realPath,
      entry.modifiedMs,
      entry.size,
      def.probeCmd,
      def.probeArgs.join(' '),
      def.probePattern,
    ].join('|');

    return _probeCache.putIfAbsent(key, () => _runProbe(entry, def));
  }

  static Future<double?> _runProbe(FileEntry entry, GeneratorDef def) async {
    final args = def.probeArgs
        .map((arg) => arg.replaceAll('%INPUT%', entry.realPath))
        .toList();
    try {
      final result = await _run(def.probeCmd!, args, def.timeout);
      if (result.timedOut || result.exitCode != 0) {
        log.warn(
          'quick-look',
          'generator "${def.id}" probe failed (exit '
              '${result.exitCode}${result.timedOut ? ', timed out' : ''}) for '
              '${entry.realPath}: ${result.stderrTail}',
        );

        return null;
      }
      final number = _extractNumber(result.stdout, def.probePattern);
      if (number == null) {
        log.warn(
          'quick-look',
          'generator "${def.id}" probe output didn\'t contain a number for '
              '${entry.realPath}: ${result.stdout}',
        );
      }

      return number;
    } catch (error, stack) {
      log.warn(
        'quick-look',
        'generator "${def.id}" probe errored for ${entry.realPath}',
        error: error,
        stack: stack,
      );

      return null;
    }
  }

  static double? _extractNumber(String text, String? pattern) {
    if (pattern == null) return double.tryParse(text.trim());
    final match = RegExp(pattern).firstMatch(text);
    if (match == null) return null;
    final group = match.groupCount >= 1 ? match.group(1) : match.group(0);

    return group == null ? null : double.tryParse(group.trim());
  }

  static List<String> _substitute(
    List<String> args, {
    required FileEntry entry,
    required String output,
    required String cacheDir,
    required String seek,
    required int position,
  }) {
    return args
        .map(
          (arg) => arg
              .replaceAll('%INPUT%', entry.realPath)
              .replaceAll('%OUTPUT%', output)
              .replaceAll('%CACHE%', cacheDir)
              .replaceAll('%SEEK%', seek)
              .replaceAll('%POSITION%', position.toString())
              .replaceAll('%PAGE%', (position + 1).toString()),
        )
        .toList();
  }

  /// Formats [totalSeconds] as `HH:MM:SS.mmm`, the timestamp form ffmpeg's
  /// `-ss` (and most similar tools) accept.
  static String _formatSeek(double totalSeconds) {
    final ms = (totalSeconds < 0 ? 0 : totalSeconds * 1000).round();
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final milli = ms % 1000;
    String two(int v) => v.toString().padLeft(2, '0');

    return '${two(h)}:${two(m)}:${two(s)}.${milli.toString().padLeft(3, '0')}';
  }

  static Future<void> _tryDelete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static String _cacheKey(FileEntry entry, GeneratorDef def, int page) {
    final raw = [
      entry.realPath,
      entry.modifiedMs,
      entry.size,
      def.id,
      def.cmd,
      def.args.join(' '),
      page,
    ].join('|');

    return sha256.convert(utf8.encode(raw)).toString();
  }
}

class _ProcessResult {
  final int exitCode;
  final bool timedOut;
  final String stdout;
  final String stderrTail;

  const _ProcessResult(
    this.exitCode,
    this.timedOut,
    this.stdout,
    this.stderrTail,
  );
}

/// Spawns [cmd], draining stdout/stderr as they're produced. Not draining
/// them is not an option: a chatty command (ffmpeg logs per-frame progress
/// to stderr) fills the pipe buffer and blocks the child process forever
/// once nothing is reading it.
Future<_ProcessResult> _run(
  String cmd,
  List<String> args,
  Duration timeout,
) async {
  final process = await Process.start(cmd, args);
  final stdoutBuf = StringBuffer();
  final stderrTail = StringBuffer();
  process.stdout
      .transform(const SystemEncoding().decoder)
      .listen(stdoutBuf.write);
  process.stderr.transform(const SystemEncoding().decoder).listen((chunk) {
    stderrTail.write(chunk);
    if (stderrTail.length <= GeneratorRunner._stderrTailLimit) return;
    final text = stderrTail.toString();
    stderrTail
      ..clear()
      ..write(text.substring(text.length - GeneratorRunner._stderrTailLimit));
  });
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill();

      return -1;
    },
  );

  return _ProcessResult(
    exitCode,
    timedOut,
    stdoutBuf.toString(),
    stderrTail.toString(),
  );
}
