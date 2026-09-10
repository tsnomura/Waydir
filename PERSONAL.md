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

- Draggable and resizable — always centered on screen (previously anchored
  over the inactive pane in dual-pane mode; that rule was dropped since it
  fought with the wider window a compare-mode diff needs), and can be moved
  and resized like a floating panel.
- `PageUp`/`PageDown` scroll the preview (previously they paged left/right
  between files); this also works for the unfocused text preview.
- In compare mode, opening Quick Look while exactly one file is selected in
  each pane attempts a side-by-side text diff (via an external `diff -y`-style
  command, config-driven like preview generators — see below) instead of the
  normal single-file preview, opening wider to fit two columns. Falls back to
  the normal single-file preview whenever the diff command is unset, missing,
  errors or times out, or the selection stops being one-file-per-pane (e.g.
  arrowing to a different file). Added/removed/changed lines are tinted using
  the same colors as compare mode's own row decorations.
- Fixed: the scroll controller wasn't attached at all on Windows, so scrolling
  silently did nothing there.
- Fixed: stepping the cursor with the arrow keys right after Quick Look opened
  on a file selected some other way (not through cursor navigation) jumped to
  the start/end of the file list instead of stepping from the file on screen.
- Fixed: stepping to another file with the arrow keys could leave the header
  showing the new file's name while the body kept showing the previous
  file's content, until something else forced a rebuild. The async preview
  loader kept rendering the old cache entry for the frames between the
  cache key changing and the new file's load finishing, and previews that
  key a fresh child widget off the file path (e.g. the text editor) baked
  that stale content in as their initial value, permanently.

### Compare diff command

The command Quick Look runs for the compare-mode diff preview is configurable,
the same way preview generators are: drop a `compare_diff.json` in Waydir's
application support directory (next to `generators/`, e.g.
`%APPDATA%\Waydir\compare_diff.json` on Windows) with `cmd`, `args`
(`%LEFT%`/`%RIGHT%`/`%WIDTH%` placeholders) and an optional `timeoutSeconds`.
Falls back to plain `diff -y --strip-trailing-cr` on `PATH` when the file is
missing — `--strip-trailing-cr` matters whenever either file has Windows CRLF
line endings, which `diff` otherwise treats as part of each line's content
rather than a terminator, corrupting every line's right-hand column. `%WIDTH%`
is a fixed generous constant, not the live pane width, since `-y` truncates
(rather than wraps) lines past it and Quick Look lays the two columns out
itself — re-running the command on every resize to keep it in sync isn't
worth the flicker. Runs with the user's full privileges; only point this at a
command you trust, same as generators.

Its output is decoded as UTF-8 (matching Quick Look's normal text preview),
not the OS's legacy codepage — decoding as the latter garbled any non-ASCII
content on non-English Windows installs, since `diff` just echoes the source
files' own UTF-8 bytes back verbatim.

Relevant commits: `9e82bb3`, `03bbfc7`, `070098a`, `a2aee71`, `cc1bdfd`,
`6513cb6`, `8f36b93`, `f93b97d`.

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

## Compare directories on network drives and sftp

`F8` compare now works against mapped/UNC network drives, not just local
disks — the restriction only ever needed to exclude Waydir's own virtual
`smb://`/`sftp://` filesystems, not real (if slow) OS-level network paths.
`sftp://` itself is now allowed too (Waydir's own `smb://` gvfs-mount alias
still isn't — see below).

- Comparing a network path (UNC/mapped drive, or now `sftp://`) defaults
  `Recursive` to off on activation, since a full recursive walk over a slow
  connection can take a long time — the user opts in explicitly rather
  than triggering it by accident. Recursive listing over sftp always uses
  the plain per-directory fallback walk (one round trip per directory) —
  there's no native fast-walker for a virtual filesystem, just the same
  dispatch every other sftp file op already goes through.
- While a comparison is running, a dedicated Cancel control (with the `Esc`
  shortcut shown) sits next to the "Comparing…" label, and the close button's
  tooltip/color reflect that it cancels an in-progress scan rather than just
  closing a finished one.
- `smb://` stays unsupported — on Linux it's a gvfs mount alias resolved to
  a real local path before any FS op touches it, not a cross-platform
  backend compare can talk to directly. Irrelevant on Windows (network
  shares are already plain UNC paths, already handled).
- Found while adding sftp support: `package:path`'s `relative()`/
  `normalize()` assume a real OS path, and on Windows in particular misparse
  the `:` in `sftp://host:port/...` as a drive-letter separator — the
  relative-path math compare uses to key its diff now branches to
  scheme-aware segment splitting (matching how `PlatformPaths.join`/
  `parentOf`/`segments` already had to, for the same reason) whenever
  either root is a `smb://`/`sftp://` URI.
- **Also found while adding sftp support — this one's an upstream bug, not
  a personal one** (present in `main` since compare was first added,
  `c09bbe7`): recursive compare's "fast path" called
  `WaydirCoreLoader.enumerate` (the native `waydir_enumerate`), which is
  actually built for delete pre-scans and always reports every entry's
  size/mtime as `0` — every file that exists on both sides was silently
  reported `identical` no matter how different its real content was,
  since `0 == 0` and `|0 - 0|` is always within tolerance. Only
  unique-to-one-side detection (which doesn't depend on metadata) ever
  worked correctly under recursive compare. It also isn't scheme-aware, so
  for an sftp root it "succeeded" with zero entries instead of ever
  reaching the sftp-capable fallback walk. Recursive compare now always
  uses the plain per-directory walk (already correct, already
  scheme-aware) — slower on huge local trees, but the native path was
  never something merely slow, it was actively wrong. Caught by a
  real-disk integration test that fails against the old code with
  "Expected: older, Actual: identical".

Relevant commits: `dec6776`, `bb6ef7f`, `a348b95`, `251abb3`.

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
- Fixed: permanently deleting a directory that's actually a reparse point
  (e.g. a cloud-sync client's placeholder folder — OneDrive-style Cloud
  Files API, `IO_REPARSE_TAG_CLOUD*`) could fail. `Link.delete()` assumes
  symlink semantics that don't apply to these; it now falls back to
  `Directory.delete(recursive: false)`, which is safe for a genuine
  symlink/junction too — Windows never deletes a reparse point's target
  through that call, only the reparse point itself.
- Right-clicking the "Date modified"/"Date created"/"Date added" column
  header now offers a "Recent dates relative" toggle directly, instead of
  only being reachable through Preferences → Appearance.

Relevant commits: `3b121a8`, `77554de`, `c9d8882`.

## Directory copy: native scan, deep-copy through reparse points

Copy's pre-scan (building the file list, totals and conflict list before any
bytes move) now goes through `waydir_core`'s parallel Rust walker instead of
a sequential Dart `listSync`/`statSync` recursion — `waydir_enumerate` gained
a `with_stat` parameter that fills in real size/mtime (free on Windows,
where `FindNextFileW` already returns it during enumeration; one extra stat
per entry elsewhere), reusing the same metadata-fill code the directory
lister already had. Bumped the native ABI to 17 since the FFI signature
changed. When the destination doesn't exist yet, conflict detection is
skipped entirely — nothing there could conflict.

Symlinks, junctions and cloud-sync placeholder folders (e.g. OneDrive-style
Cloud Files API reparse points) encountered while copying are now resolved
through and deep-copied — the real content underneath, not a recreated
link — matching how the pre-scan itself now walks (`follow_links(true)` on
the native side, which correctly stops infinite loops via `walkdir`'s
file-id cycle tracking). Fixed a bug this surfaced: `File.copy()` (Dart's
async copy path) doesn't follow reparse points and throws
`PathNotFoundException` even though the source genuinely resolves — copying
a reparse point now always forces the synchronous read/write path, which
handles it correctly.

Measured no improvement scanning a directory on a cloud-sync-backed drive
mounted as a local drive letter — the bottleneck there is the sync client's
own network latency per item, not scan-side CPU/algorithm cost, so no
client-side scan optimization helps. For that case the plan is a separate
feature: launching `robocopy` (Windows) / `rsync` (Unix) in the built-in
terminal instead of using Waydir's own copy engine.

Relevant commits: `8404fee`, `f9c874f`.
