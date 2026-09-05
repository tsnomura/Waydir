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
- A configured generator always takes priority over Waydir's built-in image/
  PDF/Markdown previews for the extensions it claims — this is what lets a
  `pdf` generator replace the native pdfium-backed preview, which doesn't
  actually work in this build.
- Results are cached by a hash of the file's path/size/mtime plus the
  generator's own command, so edits and command changes both invalidate the
  cache automatically. Failures (bad exit code, timeout, missing binary)
  always fall back to the default file icon.
- Two paging modes, both driven by `probeCmd`: `"time"` samples a fixed
  `pageCount` of evenly-spaced points across a timed source's duration (e.g.
  10 video frames every 10% of its length, 0% up to but excluding 100%);
  `"discrete"` probes the file's own real page/unit count instead (e.g. a
  PDF's actual page count via `mutool info`), since that varies per file.
  Quick Look shows prev/next controls and a page indicator either way, and
  `PageUp`/`PageDown` page through it too when a paged generator is active
  (otherwise they scroll content as usual).
- Intentionally stops at paging through still frames — a scrubber or
  playback controls are a job for an embedded video player, not Quick Look.
- Installed locally: `video-thumbnail` (`ffmpeg`/`ffprobe`, `"time"` paging)
  and `pdf-page` (`mutool`, `"discrete"` paging) in the `generators` support
  directory — not committed, since generator config is local/personal by
  design (see the trust model in `docs/generators.md`).

Relevant commits: `0907d8a`, `0522087`, `1208ae9`, `19485b1`, `68397a5`,
`32b9119`, `7abfac6`.

## LaTeX math in the Markdown preview

`$...$` (inline) and `$$...$$` (block, one line or multi-line) render as
real typeset math via `flutter_math_fork` — a pure Flutter/Dart renderer
(KaTeX-compatible subset, no WebView), reusing `flutter_svg` which was
already a dependency.

- Custom `InlineSyntax`/`BlockSyntax` registered into the `markdown`
  package parser `flutter_markdown_plus` uses under the hood, plus a
  `MarkdownElementBuilder` that turns the matched TeX source into a
  `Math.tex(...)` widget styled with the current theme's text color.
- The inline delimiter regex requires content to start/end on a
  non-whitespace, non-`$` character (Pandoc's `tex_math_dollars` rule), so
  ordinary prose mentioning two dollar amounts (`$5 and $10`) is never
  misread as one equation.
- Found while building it: a custom element builder must override
  `visitElementAfter`, not `visitText` — overriding `visitText` silently
  left the `$`-delimited span rendered as plain text (dollar signs
  stripped, content untouched) instead of typeset math.

Relevant commit: `4076f76`.

## Window state persistence

Window size and maximized/restored state are remembered across restarts
instead of always reopening at the default size.

Relevant commit: `6ee9177`.

## Pane navigation & layout

- Double-click the pane divider to swap the two panes' *active* tabs (only
  triggers when the divider itself is actually hovered) — see "Move/swap
  tabs between panes" below.
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

## Move/swap tabs between panes

A tab can move to the other pane on its own, keeping its navigation
history, selection and scroll position (the tab's `NavigationStore` moves
with it, rather than reopening the same path fresh in a new tab).

- `Ctrl+Shift+M` moves the active pane's active tab to the other pane, and
  follows it with keyboard focus. Auto-enters dual-pane mode if needed.
- Right-click a tab for a "Move Tab to Other Pane" context menu item, same
  behavior as the shortcut.
- A pane always keeps at least one tab — moving away a pane's only tab is
  refused, the same rule tab-closing already follows.
- Double-clicking the pane divider swaps the two panes' *active* tabs in
  place (each pane's other tabs are untouched) instead of swapping the
  panes' entire tab sets, using the same underlying tab-move machinery.

Found and fixed two real bugs building this:
- Tab ids were only unique *within* one pane (a per-`TabsStore` counter),
  so two independently-created panes could mint the same id — moving a tab
  across panes could then produce two tabs sharing one id (and therefore
  one `ValueKey`) in the same pane, corrupting which widget/state Flutter
  associated with which tab. Ids are now a single counter shared across
  every pane.
- The pane-swap helper could enter dual-pane mode (replacing the whole
  pane list) *after* the tab list to move from had already been read,
  leaving a stale, discarded `PaneStore` reference on a from-single-pane
  first invocation.

Relevant commits: `1f867f5`, `1690f4e`, `6b90f5d` (temporary diagnostic,
removed), `c25fbca`, `7212432`.

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
