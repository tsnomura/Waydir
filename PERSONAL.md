# Personal customizations

This documents what's different on the `personal` branch versus upstream `main`.
Unlike `CHANGELOG.md` (upstream release notes), this file tracks personal-only
features and fixes so they don't get lost across rebases.

## Terminal ↔ Waydir directory sync (`wd` / `wcd`)

A file-per-terminal signal bridge lets any shell and a Waydir pane hand each
other their current directory, in either direction.

- **`wd`** (shell → Waydir): run it in a terminal and the pane that owns that
  terminal navigates to the shell's current directory.
- **`wcd`** (Waydir → shell): run it in a terminal and the shell `cd`s into
  whatever directory the associated Waydir pane is currently showing.

Each terminal Waydir spawns gets `WAYDIR_TERMINAL_ID` and `WAYDIR_CWD_DIR` in
its environment automatically. A shell opened *outside* Waydir has neither, so
`wd`/`wcd` fall back to the currently active pane (terminal id `0`, origin
pane `active`) — on Windows this works out of the box because `WAYDIR_CWD_DIR`
is also persisted as a user environment variable.

One-time shell setup:

**PowerShell**
```powershell
function wd { $id = if ($env:WAYDIR_TERMINAL_ID) { $env:WAYDIR_TERMINAL_ID } else { 0 }; (Get-Location).Path | Set-Content -NoNewline "$env:WAYDIR_CWD_DIR\$id.txt" }
function wcd { $pane = if ($env:WAYDIR_ORIGIN_PANE) { $env:WAYDIR_ORIGIN_PANE } else { 'active' }; Set-Location (Get-Content "$env:WAYDIR_PANE_DIR_ROOT\$pane.txt") }
```

**Git Bash (MSYS)**
```bash
wd() { pwd -W > "$WAYDIR_CWD_DIR/${WAYDIR_TERMINAL_ID:-0}.txt"; }
wcd() { cd "$(cat "$WAYDIR_PANE_DIR_ROOT/${WAYDIR_ORIGIN_PANE:-active}.txt")"; }
```
Git Bash needs `pwd -W` (Windows-form path), not `$PWD` (POSIX-form) — Waydir
resolves the signal file's contents as a native path and silently drops
anything it can't resolve.

**bash/zsh (Unix)**
```bash
wd() { printf '%s' "$PWD" > "$WAYDIR_CWD_DIR/${WAYDIR_TERMINAL_ID:-0}.txt"; }
wcd() { cd "$(cat "$WAYDIR_PANE_DIR_ROOT/${WAYDIR_ORIGIN_PANE:-active}.txt")"; }
```

Relevant commits: `431feaa`, `8b04b4f`, `220d2a9`, `6d01eda`, `588be16`.

## Quick Look

- Draggable and resizable — it opens over the inactive pane instead of
  centered/fixed, and can be moved and resized like a floating panel.
- `PageUp`/`PageDown` scroll the preview (previously they paged left/right
  between files); this also works for the unfocused text preview.
- Fixed: the scroll controller wasn't attached at all on Windows, so scrolling
  silently did nothing there.

Relevant commits: `9e82bb3`, `03bbfc7`, `070098a`, `a2aee71`.

## Window state persistence

Window size and maximized/restored state are remembered across restarts
instead of always reopening at the default size.

Relevant commit: `6ee9177`.

## Pane navigation & layout

- Double-click the pane divider to swap the left and right panes (only
  triggers when the divider itself is actually hovered).
- The divider's full hit width is clickable/draggable, not just the thin
  visible line.
- `Ctrl` + double-click a folder opens it in the *other* pane.
- `Shift` + double-click a folder (or `Shift`+click in the sidebar) opens it
  in a new tab.
- `Ctrl+Shift` + double-click a folder opens it in a new tab in the other
  pane.
- Window/pane resize edge hit areas were widened so they're easier to grab.
- `F8` compare now toasts an explanation when it can't start (not in dual-pane
  mode, or one side isn't a local folder) instead of silently doing nothing.

Relevant commits: `4bc5295`, `cf9dbdd`, `540a503`, `2504f49`, `63ba23b`,
`194a146`, `bf84058`, `e3b8a68`.

## Windows Terminal integration

- The terminal shell picker offers installed Windows Terminal profiles
  directly, not just raw shell executables.
- Fixed: `%VAR%` references inside a Windows Terminal profile's commandline
  weren't expanded before launch.

Relevant commits: `20f44fd`, `4cdab3a`.

## SFTP reliability fixes

- Reconnect and re-prompt for credentials when an SFTP session drops instead
  of leaving the pane stuck.
- Reconnect works even from a fully-evicted session, and retries on app
  resume.
- Concurrent reconnect attempts for the same root are coalesced instead of
  racing.
- Symlinked directories now resolve correctly when listing over SFTP.

Relevant commits: `550baa7`, `b273adc`, `e92c5b5`, `c5ec4d4`.

## Other fixes

- Changing the sort key now preserves the prior sort order as a tiebreak
  instead of resetting it.

Relevant commit: `3b121a8`.
