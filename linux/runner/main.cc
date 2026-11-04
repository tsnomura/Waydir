#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>

#include "my_application.h"

#ifndef WAYDIR_PERSONAL_LABEL
#define WAYDIR_PERSONAL_LABEL ""
#endif

namespace {

std::string ExecutableDirectory() {
  char buffer[4096];
  ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (length <= 0) {
    return ".";
  }
  std::string path(buffer, length);
  size_t slash = path.find_last_of('/');
  return slash == std::string::npos ? "." : path.substr(0, slash);
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
                     "/data/flutter_assets/assets/cli_help.txt");
  std::ostringstream text;
  text << file.rdbuf();
  return text.str();
}

bool HandleCliQuery(int argc, char** argv) {
  bool help = false;
  bool version = false;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      help = true;
    } else if (strcmp(argv[i], "-v") == 0 ||
               strcmp(argv[i], "--version") == 0) {
      version = true;
    }
  }
  if (!help && !version) {
    return false;
  }
  std::string text = help ? HelpText() : VersionText();
  fwrite(text.data(), 1, text.size(), stdout);
  fflush(stdout);
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (HandleCliQuery(argc, argv)) {
    return 0;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
