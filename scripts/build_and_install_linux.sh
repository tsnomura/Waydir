#!/usr/bin/env bash
# Builds the Linux release bundle (with the personal version info shown in
# About) and installs it to ~/.local/share/waydir, symlinked from
# ~/bin/waydir. Rebuilds the native waydir_core first if it is missing.
# Uses whichever flutter is on PATH. Prints every command it runs.
set -euxo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

command -v flutter >/dev/null || {
  echo "flutter is not on PATH" >&2
  exit 1
}

native_lib="third_party/waydir_core/linux/libwaydir_core.so"
if [ ! -f "$native_lib" ]; then
  scripts/build_waydir_core.sh
fi

flutter pub get
scripts/build_personal.sh

bundle="build/linux/x64/release/bundle"
dest="$HOME/.local/share/waydir"
mkdir -p "$dest"
if command -v rsync >/dev/null; then
  rsync -a --delete "$bundle"/ "$dest"/
else
  find "$dest" -mindepth 1 -delete
  cp -a "$bundle"/. "$dest"/
fi

mkdir -p "$HOME/bin"
ln -sf "$dest/waydir" "$HOME/bin/waydir"

"$HOME/bin/waydir" --version
