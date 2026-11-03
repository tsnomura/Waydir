#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"
skills_dir="$codex_home/skills"
config="$codex_home/config.toml"
signal_dir="${WAYDIR_CWD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/waydir/cwd_signals}"

if [ ! -d "$signal_dir" ]; then
  echo "error: $signal_dir does not exist; start Waydir once first" >&2
  exit 1
fi
signal_dir="$(cd "$signal_dir" && pwd -P)"

mkdir -p "$skills_dir"
for skill in "$here"/*/; do
  [ -f "$skill/SKILL.md" ] || continue
  name="$(basename "$skill")"
  rm -rf "${skills_dir:?}/$name"
  cp -r "$skill" "$skills_dir/$name"
  echo "installed skill: $skills_dir/$name"
done

mkdir -p "$codex_home"
touch "$config"
if grep -qF "\"$signal_dir\"" "$config"; then
  echo "already writable in $config: $signal_dir"
  exit 0
fi

cp "$config" "$config.bak"
if ! grep -qE '^\[sandbox_workspace_write\][[:space:]]*$' "$config"; then
  {
    [ -s "$config" ] && echo
    echo '[sandbox_workspace_write]'
    echo "writable_roots = [\"$signal_dir\"]"
  } >> "$config"
elif awk '
  /^\[sandbox_workspace_write\][[:space:]]*$/ { inside = 1; next }
  /^\[/ { inside = 0 }
  inside && /^[[:space:]]*writable_roots[[:space:]]*=/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$config"; then
  awk -v dir="$signal_dir" '
    /^\[sandbox_workspace_write\][[:space:]]*$/ { inside = 1; print; next }
    /^\[/ { inside = 0 }
    inside && !done && /^[[:space:]]*writable_roots[[:space:]]*=[[:space:]]*\[/ {
      sub(/\[/, "[\"" dir "\", ")
      done = 1
    }
    { print }
  ' "$config.bak" > "$config"
else
  awk -v dir="$signal_dir" '
    { print }
    /^\[sandbox_workspace_write\][[:space:]]*$/ {
      print "writable_roots = [\"" dir "\"]"
    }
  ' "$config.bak" > "$config"
fi
echo "allowed in $config (backup: $config.bak): $signal_dir"
echo "restart Codex to apply"
