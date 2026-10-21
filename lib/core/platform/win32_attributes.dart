import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart'
    show
        COINIT_APARTMENTTHREADED,
        COINIT_DISABLE_OLE1DDE,
        CoInitializeEx,
        CoUninitialize,
        SHELLEXECUTEINFO,
        SW_SHOWNORMAL,
        ShellExecuteEx;

const _fileAttributeHidden = 0x2;
const _fileAttributeSystem = 0x4;
const _invalidFileAttributes = 0xFFFFFFFF;

DynamicLibrary? _kernel32;
int Function(Pointer<Utf16>)? _getFileAttributesW;

const _seeMaskNoAsync = 0x100;
const _oaifAllowRegistration = 0x1;
const _oaifRegisterExt = 0x2;
const _oaifExec = 0x4;

final class _OpenAsInfo extends Struct {
  external Pointer<Utf16> pcszFile;
  external Pointer<Utf16> pcszClass;
  @Int32()
  external int oaifInFlags;
}

void _ensureKernel32() {
  if (_kernel32 != null) return;
  _kernel32 = DynamicLibrary.open('kernel32.dll');
  _getFileAttributesW = _kernel32!
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('GetFileAttributesW');
}

bool isHiddenOnWindows(String path) {
  if (!Platform.isWindows) return false;
  _ensureKernel32();
  final pathPtr = path.toNativeUtf16();
  try {
    final attrs = _getFileAttributesW!(pathPtr);
    if (attrs == _invalidFileAttributes) return false;

    return (attrs & _fileAttributeHidden) != 0 ||
        (attrs & _fileAttributeSystem) != 0;
  } finally {
    calloc.free(pathPtr);
  }
}

Future<void> shellOpenOnWindows(String path) async {
  if (!Platform.isWindows) return;
  await Isolate.run(() => _shellExecute(path, null));
}

/// Launches [appExe] with [filePath] as its argument via the shell. Works for
/// classic Win32 apps; the shell resolves PATH and app paths for us.
Future<bool> shellOpenWithAppOnWindows(String appExe, String filePath) async {
  if (!Platform.isWindows) return false;

  return Isolate.run(() => _shellExecute(appExe, '"$filePath"'));
}

Future<bool> showOpenWithDialogOnWindows(String path) async {
  if (!Platform.isWindows) return false;

  return Isolate.run(() => _openWithDialog(path));
}

bool _openWithDialog(String path) {
  final hr = CoInitializeEx(
    nullptr,
    COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
  );
  final open = DynamicLibrary.open('shell32.dll')
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<_OpenAsInfo>),
        int Function(int, Pointer<_OpenAsInfo>)
      >('SHOpenWithDialog');
  final info = calloc<_OpenAsInfo>();
  final file = path.toNativeUtf16();
  try {
    info.ref
      ..pcszFile = file
      ..pcszClass = nullptr
      ..oaifInFlags = _oaifAllowRegistration | _oaifRegisterExt | _oaifExec;

    return open(0, info) >= 0;
  } finally {
    calloc.free(info);
    calloc.free(file);
    if (hr >= 0) CoUninitialize();
  }
}

bool _shellExecute(String file, String? parameters) {
  final hr = CoInitializeEx(
    nullptr,
    COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
  );
  final info = calloc<SHELLEXECUTEINFO>();
  final verb = 'open'.toNativeUtf16();
  final filePtr = file.toNativeUtf16();
  final paramsPtr = parameters?.toNativeUtf16() ?? nullptr;
  try {
    info.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNoAsync
      ..lpVerb = verb
      ..lpFile = filePtr
      ..lpParameters = paramsPtr
      ..nShow = SW_SHOWNORMAL;

    return ShellExecuteEx(info) != 0;
  } finally {
    calloc.free(info);
    calloc.free(verb);
    calloc.free(filePtr);
    if (paramsPtr != nullptr) calloc.free(paramsPtr);
    if (hr >= 0) CoUninitialize();
  }
}

DynamicLibrary? _shlwapi;
int Function(
  int,
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Uint32>,
)?
_assocQueryStringW;

void _ensureShlwapi() {
  if (_shlwapi != null) return;
  _shlwapi = DynamicLibrary.open('shlwapi.dll');
  _assocQueryStringW = _shlwapi!
      .lookupFunction<
        Int32 Function(
          Uint32,
          Int32,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          int,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Uint32>,
        )
      >('AssocQueryStringW');
}

/// ASSOCSTR values from shlwapi.h
const assocStrCommand = 1;
const assocStrExecutable = 2;
const assocStrFriendlyAppName = 4;

/// Wraps `AssocQueryStringW`. [assoc] is typically a file extension
/// (e.g. `.png`) or a ProgId. Returns null when no association exists.
String? assocQueryStringOnWindows(int str, String assoc) {
  if (!Platform.isWindows) return null;
  _ensureShlwapi();
  final assocPtr = assoc.toNativeUtf16();
  final sizePtr = calloc<Uint32>();
  try {
    final probe = _assocQueryStringW!(
      0,
      str,
      assocPtr,
      nullptr,
      nullptr,
      sizePtr,
    );
    final needed = sizePtr.value;
    if (probe != 0 && needed == 0) return null;
    final outPtr = calloc<Uint16>(needed + 1).cast<Utf16>();
    try {
      final hr = _assocQueryStringW!(
        0,
        str,
        assocPtr,
        nullptr,
        outPtr,
        sizePtr,
      );
      if (hr != 0) return null;
      final value = outPtr.toDartString();

      return value.isEmpty ? null : value;
    } finally {
      calloc.free(outPtr);
    }
  } finally {
    calloc.free(assocPtr);
    calloc.free(sizePtr);
  }
}
