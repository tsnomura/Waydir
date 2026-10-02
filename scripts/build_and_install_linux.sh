#!/usr/bin/env bash
# Builds the Linux release bundle and installs it to ~/.local/share/waydir,
# symlinked from ~/bin/waydir. Rebuilds the native waydir_core first if it
# is missing. Prints every command it runs.
set -euxo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

export PATH="$HOME/development/flutter/bin:$PATH"

native_lib="third_party/waydir_core/linux/libwaydir_core.so"
if [ ! -f "$native_lib" ]; then
  scripts/build_waydir_core.sh
fi

flutter pub get
flutter build linux --release

dest="$HOME/.local/share/waydir"
rsync -a --delete build/linux/x64/release/bundle/ "$dest"/

mkdir -p "$HOME/bin"
ln -sf "$dest/waydir" "$HOME/bin/waydir"

"$HOME/bin/waydir" --version
