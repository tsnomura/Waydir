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

## Quick Look preview generators

Config-driven preview generators let Quick Look show a raster preview for
file types Waydir has no built-in renderer for, by delegating the conversion
to an external command instead of writing a native renderer. Full details,
config schema and the trust model are in [`docs/generators.md`](docs/generators.md).

- One `.json` file per generator in the `generators` support directory maps
  a set of extensions to a command template (`%INPUT%`/`%OUTPUT%`/`%CACHE%`
  placeholders), e.g. extracting a video thumbnail via `ffmpeg`.
- Generators only fill gaps — they never override Waydir's built-in image/
  PDF/Markdown previews.
- Results are cached by a hash of the file's path/size/mtime plus the
  generator's own command, so edits and command changes both invalidate the
  cache automatically. Failures (bad exit code, timeout, missing binary)
  always fall back to the default file icon.
- A generator can declare `pageCount` + `probeCmd` to page through evenly-
  spaced points across a timed source (e.g. 10 video frames sampled every
  10% of its duration, 0% up to but excluding 100%). Quick Look shows prev/
  next controls and a page indicator, and `PageUp`/`PageDown` page through it
  too when a multi-page generator is active (otherwise they scroll content
  as usual).
- Intentionally stops at paging through still frames — a scrubber or
  playback controls are a job for an embedded video player, not Quick Look.

Relevant commits: `0907d8a`, `0522087`, `1208ae9`, `19485b1`, `68397a5`.

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

## Compare directories on network drives

`F8` compare now works against mapped/UNC network drives, not just local
disks — the restriction only ever needed to exclude Waydir's own virtual
`smb://`/`sftp://` filesystems, not real (if slow) OS-level network paths.

- Comparing a network path defaults `Recursive` to off on activation, since a
  full recursive walk over a slow share can take a long time — the user
  opts in explicitly rather than triggering it by accident.
- While a comparison is running, a dedicated Cancel control (with the `Esc`
  shortcut shown) sits next to the "Comparing…" label, and the close button's
  tooltip/color reflect that it cancels an in-progress scan rather than just
  closing a finished one.

Relevant commits: `dec6776`, `bb6ef7f`.

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
