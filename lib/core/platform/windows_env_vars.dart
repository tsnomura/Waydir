import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../logging/app_logger.dart';

/// Persists user environment variables (`HKCU\Environment`) and broadcasts
/// the change, so shells opened after this runs — including ones this app
/// never spawned — see them without a logout. Windows-only; a no-op
/// elsewhere.
class WindowsEnvVars {
  WindowsEnvVars._();

  /// Sets each entry in [vars], skipping ones already at that value, and
  /// broadcasts `WM_SETTINGCHANGE` once if anything changed.
  static void persist(Map<String, String> vars) {
    if (!Platform.isWindows) return;
    var changed = false;
    for (final entry in vars.entries) {
      if (_read(entry.key) == entry.value) continue;
      if (_write(entry.key, entry.value)) changed = true;
    }
    if (changed) _broadcastChange();
  }

  static bool _write(String name, String value) {
    final hKeyPtr = calloc<IntPtr>();
    final subKeyPtr = 'Environment'.toNativeUtf16();
    try {
      final created = RegCreateKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        nullptr,
        0,
        KEY_WRITE,
        nullptr,
        hKeyPtr,
        nullptr,
      );
      if (created != ERROR_SUCCESS) return false;
      final valueNamePtr = name.toNativeUtf16();
      final valuePtr = value.toNativeUtf16();
      try {
        final set = RegSetValueEx(
          hKeyPtr.value,
          valueNamePtr,
          0,
          REG_SZ,
          valuePtr.cast<Uint8>(),
          (value.length + 1) * 2,
        );

        return set == ERROR_SUCCESS;
      } finally {
        calloc.free(valueNamePtr);
        calloc.free(valuePtr);
        RegCloseKey(hKeyPtr.value);
      }
    } catch (e, st) {
      log.warn(
        'terminal',
        'failed to persist env var $name',
        error: e,
        stack: st,
      );

      return false;
    } finally {
      calloc.free(subKeyPtr);
      calloc.free(hKeyPtr);
    }
  }

  static String? _read(String name) {
    final hKeyPtr = calloc<IntPtr>();
    final subKeyPtr = 'Environment'.toNativeUtf16();
    try {
      final opened = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        KEY_READ,
        hKeyPtr,
      );
      if (opened != ERROR_SUCCESS) return null;
      final valueNamePtr = name.toNativeUtf16();
      final sizePtr = calloc<Uint32>();
      try {
        var status = RegQueryValueEx(
          hKeyPtr.value,
          valueNamePtr,
          nullptr,
          nullptr,
          nullptr,
          sizePtr,
        );
        if (status != ERROR_SUCCESS || sizePtr.value == 0) return null;
        final dataPtr = calloc<Uint8>(sizePtr.value);
        try {
          status = RegQueryValueEx(
            hKeyPtr.value,
            valueNamePtr,
            nullptr,
            nullptr,
            dataPtr,
            sizePtr,
          );
          if (status != ERROR_SUCCESS) return null;

          return dataPtr.cast<Utf16>().toDartString();
        } finally {
          calloc.free(dataPtr);
        }
      } finally {
        calloc.free(valueNamePtr);
        calloc.free(sizePtr);
      }
    } catch (_) {
      return null;
    } finally {
      calloc.free(subKeyPtr);
      RegCloseKey(hKeyPtr.value);
      calloc.free(hKeyPtr);
    }
  }

  static void _broadcastChange() {
    final lParamPtr = 'Environment'.toNativeUtf16();
    final resultPtr = calloc<IntPtr>();
    try {
      SendMessageTimeout(
        HWND_BROADCAST,
        WM_SETTINGCHANGE,
        0,
        lParamPtr.address,
        SMTO_ABORTIFHUNG,
        5000,
        resultPtr,
      );
    } finally {
      calloc.free(lParamPtr);
      calloc.free(resultPtr);
    }
  }
}
