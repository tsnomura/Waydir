#include "utils.h"

#include <fcntl.h>
#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <fstream>
#include <iostream>
#include <sstream>

#ifndef WAYDIR_PERSONAL_LABEL
#define WAYDIR_PERSONAL_LABEL ""
#endif

namespace {

bool IsRedirected(DWORD id) {
  HANDLE handle = ::GetStdHandle(id);
  if (handle == nullptr || handle == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD type = ::GetFileType(handle);
  return type == FILE_TYPE_DISK || type == FILE_TYPE_PIPE;
}

void PointStdoutAtConsole() {
  FILE *unused;
  if (freopen_s(&unused, "CONOUT$", "w", stdout) == 0) {
    ::SetStdHandle(STD_OUTPUT_HANDLE, reinterpret_cast<HANDLE>(
                                          _get_osfhandle(_fileno(stdout))));
  }
}

std::wstring ExecutableDirectory() {
  wchar_t buffer[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  std::wstring path(buffer, length);
  size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

std::string VersionText() {
  std::ostringstream text;
  text << "Waydir " << FLUTTER_VERSION_MAJOR << "." << FLUTTER_VERSION_MINOR
       << "." << FLUTTER_VERSION_PATCH;
  std::string personal = WAYDIR_PERSONAL_LABEL;
  if (!personal.empty()) {
    text << " (personal " << personal << ")";
  }
  text << "\n";
  return text.str();
}

std::string HelpText() {
  std::ifstream file(ExecutableDirectory() +
                         L"\\data\\flutter_assets\\assets\\cli_help.txt",
                     std::ios::binary);
  std::ostringstream text;
  text << file.rdbuf();
  return text.str();
}

}  // namespace

bool HandleCliQuery(const std::vector<std::string> &arguments,
                    bool attached_console) {
  bool help = false;
  bool version = false;
  for (const std::string &argument : arguments) {
    if (argument == "-h" || argument == "--help") {
      help = true;
    } else if (argument == "-v" || argument == "--version") {
      version = true;
    }
  }
  if (!help && !version) {
    return false;
  }
  if (attached_console && !IsRedirected(STD_OUTPUT_HANDLE)) {
    PointStdoutAtConsole();
  }
  _setmode(_fileno(stdout), _O_BINARY);
  std::string text = help ? HelpText() : VersionText();
  fwrite(text.data(), 1, text.size(), stdout);
  fflush(stdout);
  return true;
}

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
