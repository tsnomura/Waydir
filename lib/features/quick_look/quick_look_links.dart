import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../core/keyboard/keyboard_shortcuts.dart';
import '../../core/models/file_entry.dart';
import '../../core/platform/platform_paths.dart';
import '../../i18n/strings.g.dart';
import 'code_editor.dart';
import 'quick_look_common.dart';
import 'quick_look_reload.dart';

String? resolveLocalLink(String href, String basePath) {
  if (PlatformPaths.isSftpUri(basePath)) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'file') return null;
  if (uri.path.isEmpty) return null;
  final Uri resolved;
  try {
    resolved = uri.hasScheme
        ? uri.removeFragment()
        : Uri.directory(p.dirname(basePath)).resolveUri(uri.removeFragment());
  } on FormatException {
    return null;
  }
  if (resolved.scheme != 'file') return null;
  final String path;
  try {
    path = p.normalize(resolved.toFilePath());
  } on UnsupportedError {
    return null;
  }
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (!markdownExts.contains(ext)) return null;

  return path;
}

Future<FileEntry?> loadLinkTarget(String path) async {
  final file = File(path);
  try {
    if (!await file.exists()) return null;
  } on FileSystemException {
    return null;
  }

  return FileEntry.fromFileSystemEntity(file);
}

bool isQuickLookBackKey(LogicalKeyboardKey key) {
  if (AppShortcuts.isControl || AppShortcuts.isShift) return false;
  if (key == LogicalKeyboardKey.arrowLeft) return AppShortcuts.isAlt;

  return key == LogicalKeyboardKey.backspace && !AppShortcuts.isAlt;
}

class QuickLookLinkHistory {
  final _stack = <FileEntry>[];
  String? _baseKey;

  bool get canGoBack => _stack.isNotEmpty;

  FileEntry? resolve(FileEntry? base) {
    final key = base?.realPath;
    if (key != _baseKey) {
      _baseKey = key;
      _stack.clear();
    }

    return _stack.isEmpty ? base : _stack.last;
  }

  void push(FileEntry entry) => _stack.add(entry);

  void back() {
    if (_stack.isNotEmpty) _stack.removeLast();
  }
}

Future<bool> confirmLeaveEditor(
  BuildContext context,
  CodeEditorController controller,
) async {
  if (!controller.dirty.value) return true;
  final choice = await confirmUnsavedChanges(
    context,
    t.quickLook.unsavedMessage,
  );
  if (!context.mounted || choice == UnsavedChoice.cancel) return false;
  if (choice == UnsavedChoice.save) return await controller.save();

  return true;
}
