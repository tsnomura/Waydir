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
pane `active`) — this works out of the box because `WAYDIR_CWD_DIR` and
`WAYDIR_PANE_DIR_ROOT` are also persisted: as user environment variables in
the registry on Windows (`WindowsEnvVars`), or via a sourced script wired
into `~/.bashrc` / `~/.zshrc` / `~/.bash_profile` / `~/.zprofile` /
`~/.profile` on Linux/macOS (`UnixEnvVars`). Either way, only shells opened
*after* Waydir has run at least once pick it up.

One-time shell setup — the `wd`/`wcd` functions themselves still need adding
once per shell (Waydir only persists the env vars they read, not the
functions):

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
- In compare mode, Quick Look on a file that exists on both sides attempts a
  side-by-side text diff (via an external `diff -y`-style command,
  config-driven like preview generators — see below) instead of the normal
  single-file preview, opening wider to fit two columns. The pair is found
  automatically by relative path — nothing needs to be marked — and follows
  the cursor, so arrowing to another file inside Quick Look diffs that file
  against its counterpart. Marking exactly one file in each pane still
  overrides the automatic pair (to diff two differently named files). Pairs
  where either side is on sftp get the normal preview, since the external
  command can't read `sftp://` paths. Before running the diff command the
  two files are compared byte for byte (the same native check compare uses,
  skipped when sizes differ, stopping at the first difference); a
  byte-identical pair gets the normal preview instead, titled
  `name (identical)`, with editing and playback available as usual. The
  verdict is cached per pair while Quick Look stays open. Cloud-only
  (OneDrive placeholder) files aren't read, so they go straight to the diff.
  Falls back to the normal single-file preview whenever the diff command is
  unset, missing, errors or times out.
  Added/removed/changed lines are tinted using the same colors as compare
  mode's own row decorations.
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
`%APPDATA%\dev.waydir\Waydir\compare_diff.json` on Windows) with `cmd`, `args`
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
`6513cb6`, `8f36b93`, `f93b97d`, `1882923`.

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
- Intentionally stops at paging through still frames — a scrubber or video
  playback controls are a job for an embedded video player, not Quick Look.
  Audio playback is the one exception; see "Quick Look audio playback" below.
- Installed locally: `video-thumbnail` (`ffmpeg`/`ffprobe`, `"time"` paging),
  `pdf-page` (`mutool`, `"discrete"` paging), `svg-preview` (`resvg`, no
  paging), `3d-model` (`f3d` offscreen render of stl/obj/ply/gltf/glb/3mf/
  fbx/dae/STEP/IGES/VTK etc., angled camera, transparent background),
  `comsol-mph` and `office-thumbnail` in the `generators` support
  directory — not committed, since generator config is local/personal by
  design (see the trust model in `docs/generators.md`).
- The last two need no extra tools on Windows: COMSOL `.mph`, Office
  (pptx/docx/xlsx) and OpenDocument files are zips that can carry a preview
  image, and a PowerShell one-liner using .NET's `ZipFile` pulls out just
  that entry (reading the zip's central directory, not the whole file). On
  Linux/macOS, both use `unzip -p` instead (same one-entry read, via the
  near-universally-installed `unzip`) — `office-thumbnail` tries each
  candidate entry name in turn via a small `sh -c` loop and stops at the
  first that exists, since which one is present depends on which app wrote
  the file. `.mph` has `modelimage_large.png` (1024x768) / `modelimage.png`
  — always present in COMSOL's Application Library samples, usually absent
  from users' own models unless a thumbnail was set. pptx has
  `docProps/thumbnail.jpeg` by default but only ~256x192 (blurry in Quick
  Look); docx/xlsx only when "save thumbnail" was on; OpenDocument always
  has `Thumbnails/thumbnail.png`.
- Opening Quick Look on a paged file (mp4/pdf-style) now generates every
  remaining page in the background, one at a time, so paging forward is
  usually instant instead of waiting per page — stops if you close Quick
  Look or move to a different file first.
- **Preferences → Quick Look → Preview generators**: list/add/edit/delete
  generators without leaving the app, plus a "Reload" button and a clickable
  path to the generators folder (opens it as a new tab) and a link to the
  full `docs/generators.md` guide. The add/edit form only covers the simple
  scalar fields (`id`/`extensions`/`cmd`/`timeoutSeconds`/`outputExt`) —
  `args`/paging/probe fields stay hand-edited via an "Edit JSON" button that
  opens the file in the OS default editor, and are preserved untouched
  across a form-based edit of the basic fields. A generator created through
  the form gets `_help`/`_help_*` string fields (JSON has no comment syntax;
  Waydir ignores any key starting with `_`) explaining each field.
- **The file grid also shows a generator's output as a thumbnail** (always
  on, no separate setting — reuses the same cache Quick Look does), first
  page/frame only. A ~200ms per-tile settle delay avoids generating for
  tiles only ever flashed past while scrolling, and an app-wide concurrency
  gate (`Platform.numberOfProcessors.clamp(2, 4)`) caps how many
  generator/probe processes run at once so scrolling a folder full of
  matching files doesn't spawn a burst of them. A genuinely failed
  page/probe (bad command, no output) is remembered so it isn't retried
  every time its tile scrolls back into view; a *timeout* deliberately isn't
  remembered the same way, since under concurrent load it can be transient
  rather than a real, permanent failure.
- Fixed while building grid thumbnails: the temp file each generation wrote
  to before renaming into the cache was named from a wall-clock timestamp —
  fine when at most one generation ever ran at a time (Quick Look previews
  one file, and its own page-prefetch is sequential), but once the grid
  could request thumbnails for many *different* files concurrently, two
  generations landing on the same low-resolution timestamp could race to
  rename each other's rendered output onto the wrong file's cache path —
  a real, persistent (survives restarts) cross-file mixup, not just a
  transient display glitch. Fixed by naming the temp file after the same
  cache key used for the final path (unique per in-flight generation by
  construction, since in-flight requests are already deduped by that key).
- Fixed while building grid thumbnails: `_GridTile`'s items in the
  `GridView.builder` have no per-file `Key`, so Flutter can reuse a
  thumbnail widget's State (including an already-resolved generator preview
  path) for a different file entirely when the grid's list changes
  underneath it (sort, refresh, filter) — the new tile then kept showing
  the old file's image until something else forced a full remount. Fixed by
  detecting the entry's identity changing in `didUpdateWidget` and resetting
  the resolved path there, the same pattern `AsyncRetain` already uses
  elsewhere in Quick Look.

Relevant commits: `0907d8a`, `0522087`, `1208ae9`, `19485b1`, `68397a5`,
`32b9119`, `7abfac6`, `8a0c945`, `7fb56ac`, `2337131`.

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
- `Ctrl` + double-click a folder (or `Ctrl`+click a sidebar item) opens it in
  a new tab in the *same* pane; `Shift` + double-click (or `Shift`+click in
  the sidebar) opens it in a new tab in the *other* pane, and switches
  keyboard/toolbar focus there too so the new tab is immediately visible.
  `Ctrl` held together with `Shift` doesn't change the meaning — `Shift`
  alone already means "other pane". Deliberately mirrors the browser
  convention (`Ctrl`+click a link = new tab, `Shift`+click = new window)
  with "pane" standing in for "window", rather than an invented scheme.
  There's deliberately no way to make the double-click/sidebar-click reuse
  an *existing* tab in the other pane — before tabs existed, the only way to
  drill sideways into a subfolder (à la AmigaOS Directory Opus) was to
  overwrite the other pane's view, but now that tabs exist, always opening a
  fresh one is strictly better (nothing is lost, and back-navigation still
  works) — so that "reuse" concept was designed out entirely rather than
  kept as a third option.
- The active pane's toolbar (back/forward/up + address bar) shows a thin
  accent-colored underline instead of the neutral divider color, so it's
  obvious which pane is active without relying on the more subtle overlay
  the two panes already had (a light dark tint over whichever pane is
  *inactive* — unchanged, this is additive to that).
- Window/pane resize edge hit areas were widened so they're easier to grab
  (later reshaped where that widening swallowed adjacent scrollbars — see
  "Resize edges no longer swallow scrollbars" below).
- `F8` compare now toasts an explanation when it can't start (not in dual-pane
  mode, or one side isn't a local folder) instead of silently doing nothing.

Relevant commits: `4bc5295`, `cf9dbdd`, `540a503`, `2504f49`, `63ba23b`,
`194a146`, `bf84058`, `e3b8a68`, `c680443`.

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
  reaching the sftp-capable fallback walk. Recursive compare switched to
  the plain per-directory walk (already correct, already scheme-aware) —
  slower on huge local trees, but the native path was never something
  merely slow, it was actively wrong. Caught by a real-disk integration
  test that fails against the old code with "Expected: older, Actual:
  identical".
- Later, once `waydir_enumerate` gained `with_stat` for copy pre-scans
  (see "Directory copy" below), local recursive compare went back to the
  native parallel walk — now with real size/mtime — run in an
  `FsWorkerPool` isolate (a new `walk` op next to `list`) so it doesn't
  block the UI. `sftp://` roots still use the per-directory walk. The same
  integration test guards it: flipping `withStat` back off reproduces
  "Expected: older, Actual: identical". Differences from the Dart walk:
  the native walk can't be interrupted (Cancel clears the UI immediately,
  but the scan finishes in the background and is discarded), unreadable
  subfolders are skipped instead of failing the whole compare, and
  symlink cycles terminate (cycles are tracked by file id).

Relevant commits: `dec6776`, `bb6ef7f`, `a348b95`, `251abb3`, `660e3fd`.

## Compare: status column, content check, ghost rows, linked panes

### Status: color for the state, glyph for the direction

The old rendering mixed both into one faint cue — an 18% background tint
plus a 9px glyph on the file icon's corner — and gave newer/older their own
colors, so a file whose content had changed but whose mtime differed showed
as "newer"/"older" and never as "different". In practice `≠` almost never
fired: it required a size difference with mtimes within the 2s tolerance.

- Color now says *what* the state is, the glyph says *which way*:
  green `+` only on this side; orange `↑` newer, `↓` older, `≠` same
  timestamp but different content; identical rows stay plain.
- List view gets a dedicated status column left of the icon: a solid,
  icon-sized chip with the glyph in bold. It stays visible on the cursor,
  hovered and marked rows (the old tint vanished on all three). The column
  only exists while some row carries a compare badge, and the header's
  leading slot widens with it so the columns stay aligned. Compare rows no
  longer get the background tint; tag tints are unchanged.
- Grid view shows the same chip at the thumbnail's top-left corner.
- The legend in the compare bar shows the two state swatches, a divider, and
  the `↑`/`↓`/`≠` chips.

### Content check for same-size, different-mtime pairs

A size difference already proves the content differs, and same size plus
mtimes within tolerance is treated as identical. The one case metadata can't
decide — same size, different mtime (typically a copy that didn't preserve
timestamps) — is now settled by reading the files, when both roots are local
drives: identical content → `identical`, otherwise orange `↑`/`↓`.

- Compared in the native core (`waydir_files_equal`, ABI 18) byte by byte in
  1 MiB chunks, stopping at the first difference, called in batches of 32
  from an `FsWorkerPool` isolate so the UI never blocks and Cancel takes
  effect between batches.
- Skipped (treated as different, as before) when either root is a network
  path or sftp, and for cloud-only files — OneDrive placeholders with the
  `OFFLINE`/`RECALL_ON_OPEN`/`RECALL_ON_DATA_ACCESS` attributes — since
  reading them would trigger a download. A `subst` drive counts as local
  when its target is (`GetDriveType` already reports the target's type).
- On Linux, network detection is still only `/gvfs/`, so NFS/CIFS mounts
  would still be read.

### Ghost rows

A file that exists on one side only shows up in the other pane as a ghost
row: same name, greyed out and struck through, in the position it would
sort into (size/dates borrowed from the real file, so with the same sort
both panes list the same names in the same order). Ghosts are generated for
whichever folder each pane is showing.

- The cursor can land on a ghost. Quick Look there previews the real file
  on the other side; Sync with the cursor on a ghost in the active pane and
  nothing marked copies just that item.
- Ghosts never act like files: they can't be marked (excluded from
  `selectedEntries`, and any mark that reaches one is stripped
  immediately), opened, renamed, dragged, dropped onto or context-menued,
  and they're excluded from copy/move-to-other-pane's cursor fallback,
  thumbnails, folder-size scans, the terminal path insert and the command
  palette's file list.
- Limits: a folder that exists on one side only shows just its own ghost
  row — it can't be entered. In tree view ghosts appear at the top level
  only.
- Fixed while testing: a directory-watcher refresh re-derived the cursor
  index from the raw listing, which has no ghosts, so on a busy folder
  (OneDrive under a `subst` drive here) the cursor jumped back by the
  number of ghosts above it. Cursor and anchor are now re-found by path in
  the list that's actually displayed.

### Linked panes

While compare is active the panes move together:

- Sort: the right pane uses the left pane's sort. Changing the sort from
  either pane changes the left one; the right folder's remembered sort is
  never overwritten, and the right pane goes back to its own sort when
  compare ends.
- Scroll (both ways): scrolling either pane moves the other to the same
  offset. Offsets the view applies because of the link aren't reported
  back, so the two can't fight.
- Cursor (both ways): moving the cursor moves the other pane's cursor to the
  row with the same name (ghosts included), without touching marks — only
  while both panes show the same relative folder.
- Folders (both ways): entering or leaving a subfolder takes the other pane
  to the same relative path, if it exists there.
- Limits: scroll follows by pixel offset, so rows can drift if only one
  pane has a search filter or hidden files differ. Compare still re-runs
  after a completed operation using the panes' current folders as the new
  roots, so syncing from inside a subfolder makes it the new compare root.

### Quick Look diff pairing

Covered under Quick Look above: the pair is found by relative path from the
cursor, with one marked file per pane as an explicit override.

Relevant commits: `1882923`, `d63eb9d`.

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
terminal instead of using Waydir's own copy engine — see below.

Relevant commits: `8404fee`, `f9c874f`.

## Bulk copy via the built-in terminal (robocopy/rsync/scp)

For copies where Waydir's own engine isn't the right tool — chiefly SFTP and
cloud-sync-backed drives, where the bottleneck is per-item network latency no
client-side algorithm can fix — a context menu item builds and inserts a
`robocopy`/`rsync`/`scp` command line into the built-in terminal instead,
after an options dialog to pick flags and confirm the destination. The
command is inserted but *not* run (no auto-`Enter`) so the user can review or
edit it first.

- Tool choice: `scp` whenever either side is an `sftp://` location, otherwise
  the platform default (`robocopy` on Windows, `rsync` elsewhere) — neither
  robocopy nor rsync understands Waydir's own URI scheme.
- Multi-selection is supported: rsync/scp take multiple source arguments in
  one call; robocopy (one source directory per invocation) becomes multiple
  `&&`-chained calls, one per selected folder plus one per group of selected
  files sharing a parent directory.
- robocopy specifically forces `cmd.exe` as the terminal shell regardless of
  the user's configured default profile — its `/E`-style flags get mangled
  as Unix paths under Git Bash/MSYS syntax.
- `LocationUri.path` strips the URI's leading `/`, so building an
  `user@host:/remotePath` scp spec has to re-add it manually, or scp treats
  the remote path as relative to the login's home directory instead of
  absolute.
- The context menu's tool label and the dialog's chosen tool both derive
  from one shared "what's the effective destination" helper, so an
  upload-to-sftp case can't show a stale "robocopy" label while actually
  running `scp` underneath.

Relevant commits: `bb770dc`.

## Drive-type icons on pane tabs

A pane tab's icon reflects what kind of location it's currently showing,
instead of always being a plain folder: `usb` for a removable drive,
`treeStructure` for a network drive/UNC/mapped share, `desktopTower` for an
`sftp://` connection, and `folder` (unchanged) for a regular local folder.
On Windows, a small muted drive-letter badge (e.g. `C`) sits next to the
icon too, since the icon alone doesn't say *which* local/removable/network
drive a tab is on.

Classification reuses the same drive list (`DriveStore`, already computed
for the sidebar) rather than re-deriving removable/network detection, so it
stays correct without new native calls per tab.

Relevant commits: `28cf621`.

## Embedded terminal reliability fixes

- Fixed: a terminal tab stayed open even after its shell process had
  already exited (e.g. typing `exit` in `cmd.exe`). The native pty session
  only tracked liveness via the reader thread hitting EOF, which on
  Windows never happens just because the child process exited — ConPTY
  doesn't close the master's read side on its own. Liveness now also polls
  the child process's own exit status directly.
- Fixed: a bare `Ctrl+A` inside the terminal was always hijacked into
  "select all terminal text" (for copy), silently eating the keystroke
  shells almost universally bind to "move to start of line"
  (readline/emacs convention) — a real fix, not a niche one, since this
  fires by default on Windows/Linux (`terminalCopyPasteMode` defaults to
  the mode where Ctrl+C/V/A all use the bare modifier there). Select-all
  now always requires the shift-augmented combo (`Ctrl+Shift+A` /
  `Cmd+Shift+A`) regardless of that setting, matching how copy/paste
  already degrade gracefully instead of unconditionally claiming the key.

Relevant commits: `23459d7`.

## Fixed: archive browsing and copying on Windows

How archives work, for reference: browsing never extracts anything — each
listing reads the archive's index in an `FsWorkerPool` isolate and builds
virtual entries (tar.gz/bz2/xz are decompressed in memory each time).
Extraction to `%TEMP%` happens only when real files are needed: opening an
entry extracts just that file to `waydir-archive\`, copying/moving out
stages the selection under `waydir-archive-stage\<timestamp>\` and then runs
a normal copy, and editing inside an archive (rename/delete/add) extracts
the whole thing, changes it and repacks. Formats: zip family (zip, jar,
war, apk, xpi, whl, crx, epub), tar, tar.gz/tgz, tar.bz2/tbz, tar.xz/txz.

Three Windows-only bugs, all separator or handle related:

- Folders from the second level down listed as empty (e.g.
  `mergers-windows-x86_64.zip\share\icons`): the path inside the archive is
  built with `\`, while archive entries always use `/`, so the level filter
  never matched once the inner path had a separator. The listing now
  normalizes the inner path first.
- F5 (and any copy/move out of an archive) failed: the staged source path
  was built with `/` (`…\waydir-archive-stage\123/b`), and the copy engine
  took everything after the last `\` — `123/b` — as the item name. Folders
  landed inside an extra timestamp-named folder level; files failed. Staged
  paths are now built with `package:path`.
- The archive file stayed open: zip/tar were decoded from an
  `InputFileStream` that was never closed, so Waydir kept the archive
  locked (can't be deleted or overwritten elsewhere) and leaked a handle per
  listing/extraction. Every read now closes its stream when done.

Relevant commits: `2841b3f`.

### Archive temp cleanup

Staged copies and opened entries used to stay in `%TEMP%` forever (about
400 MB had piled up here). Each Waydir process now keeps them under its own
PID subfolder — `waydir-archive-stage\<pid>\` and `waydir-archive\<pid>\` —
and holds an exclusive lock on `waydir-archive-stage\<pid>\.session.lock`
while it runs.

- On exit (a normal window close, via `AppLifecycleListener.onExitRequested`)
  the process deletes its own two folders. An entry still open in another
  app may fail to delete; it's picked up by the next startup.
- On startup, folders whose lock is no longer held (a crash, a killed
  process, or the pre-PID layout) are deleted; folders of other instances
  still running are left alone, so two Waydir windows can't delete each
  other's in-flight staging.
- A file opened from an archive is a temporary copy: edits to it were never
  written back into the archive, and closing Waydir now deletes it.

### Immediate notice when copying out of an archive

Copy/move/duplicate sources inside an archive are extracted before the real
task is queued, which on a large archive took long enough that F5 looked
ignored. The operations panel now shows an "Extracting N items from
archive" row (with a start notification) as soon as the command is issued;
it's replaced by the normal copy/move task once staging finishes, or marked
failed with the error. Cancelling it abandons the transfer — extraction
runs in a worker and can't be interrupted, but nothing gets copied.

Relevant commits: `35c52f9`.

## Fixed: renaming a file could select an unrelated file and scroll to it

Waydir remembers each folder's selection/cursor across visits
(`rememberFolderState`, on by default) and restores it whenever a folder is
loaded — but it was restoring on *every* load, including a plain same-folder
refresh, not just a genuine fresh navigation into the folder. Renaming a
file in a folder you'd visited before (with something else selected there
previously) raced the rename's own correct new-selection against that stale,
unrelated remembered one — and the stale one could win, taking the cursor
(and the list's scroll position) with it.

Fixed by only restoring a remembered folder selection when the current view
genuinely has nothing selected yet (empty selection, no cursor) — which is
true for a fresh navigation (the feature's actual intended case) but not for
a refresh of a folder you're already actively working in.

Relevant commits: `00ac0de`.

## Fixed: "delete permanently" keybind, and a stale Preferences hint

`delete_permanent` was bound to `Ctrl+Delete`, not the real Windows standard
(`Shift+Delete`) — and the Preferences hint text for the separate (and, it
turns out, non-functional) `deleteKeyBehavior` setting already claimed
*"Shift+Delete always deletes permanently"*, a promise the actual binding
didn't keep. Rebound `delete_permanent` to `Shift+Delete` to match both the
real Windows convention and that existing hint text.

Also found along the way: `deleteKeyBehavior` (Preferences → General →
"Delete key behavior", a "Move to Trash" / "Delete Permanently" choice) is
persisted but never actually read by the delete dispatch — bare `Delete`
always moves to Trash regardless of this setting. Not wiring it up for real
this round (kept as future scope); just reworded the hint text to stop
over-promising, since it previously described `deleteKeyBehavior` as
controlling the bare Delete key's default action.

Relevant commits: `d3ca1be`.

## Keyboard-oriented cleanup: Escape/Enter across everyday-workflow dialogs

Waydir bills itself as keyboard-driven, but several dialogs used during
ordinary, frequent file-management work (compress, checksum, multi-rename,
select-by-pattern, open-with, bulk-copy) were built with a raw `showDialog`
instead of the shared `showCustomDialog` machinery, and so silently lacked
its `Escape`-to-cancel / `Enter`-to-confirm handling — a `Tab` off the
autofocused text field (e.g. onto a checkbox or dropdown) left you with no
keyboard way to close the dialog at all. Deliberately scoped to the dialogs
that come up during everyday work, not settings/help dialogs — those are
rare enough that requiring the mouse there is an acceptable tradeoff, per
the actual design goal (efficient common operations, not "every widget must
be keyboard-reachable").

Extracted the key handling `showCustomDialog` already had into a reusable
`DialogKeyBindings` widget (`lib/ui/dialogs/dialog.dart`) — wraps a dialog's
content and calls `onConfirm`/`onCancel` for `Enter`/`Escape` regardless of
which control inside currently has focus — and refactored
`showCustomDialog` itself to use it too, instead of duplicating the logic.
Applied it to the six dialogs above (two of which had grown their own
ad-hoc, Escape-only version of the same thing independently).

Relevant commits: `0cbb0c5`.

## File selection: anchor-free cursor/mark model, dired commands

Reworked the file list's selection system from scratch around a private draft
spec (`selection-spec.md`, not committed — personal design notes). Core idea:
state is only ever **cursor** (a position) and **mark** (a path-keyed set) —
no invisible "anchor" the old Shift+click/Shift+arrow range logic depended on.
Every operation's result is derivable from what's currently on screen (the
existing marks, the current cursor) plus the key/click just made, never from
unseen history.

- **Keyboard**: arrows/Home/End/PgUp/PgDn move the cursor only, never
  touching marks. `Shift`+move **paints** the range between the old and new
  cursor position, excluding the destination cell (which the cursor's own
  highlight already indicates) — so one press changes exactly one item.
  "Paint" rather than toggle: the mode (mark vs. unmark) is decided once,
  from whichever cell the cursor was on when the `Shift`+move session began,
  and stays locked until a plain (unmodified) move ends the session — so a
  session paints a uniform run even if it sweeps back over a cell whose mark
  state doesn't match, rather than punching a hole in it. Tried a pure
  per-cell toggle first; it technically matched the "no anchor" philosophy
  (fully derivable from the current cursor+marks, no session state) but felt
  wrong in practice — sweeping back over ground you'd already marked could
  unmark it, and reversing direction produced results that needed real
  thought to predict. `Ctrl` always means "bigger step" (page-sized,
  mirroring text editors' `Ctrl`+arrow = word) rather than changing what the
  paint does — so `Ctrl+Shift`+move is the same paint, just over a
  page-sized range. Painting still fires (on the current cell) even when the
  cursor can't actually move because it's already at the top/bottom of the
  list; holding the key down doesn't keep re-applying it once stuck (only a
  fresh, non-repeat press does, and it's a no-op anyway since the mode is
  already locked).
- **Mouse** (superseded — see "Mouse click model" below for the current
  behavior): click originally toggled the clicked item in place (`Ctrl`+click
  a deliberate alias); `Shift`+click toggled the *inclusive* range between
  the cursor and the click. Right-click always moves the cursor to the
  target (previously did nothing when the target was already marked) —
  this part is unchanged.
- **Rubber-band**: `Shift`+drag only (can start even on top of an item — the
  row's own drag-and-drop recognizer backs off via a `HardwareKeyboard`
  Shift-check so it doesn't compete for the gesture). Also paints rather
  than toggles: the mode is decided once, from whichever item (if any) was
  under the pointer when the drag started, and every frame recomputes
  `snapshot ∪ (paths currently in the rectangle)` (mark mode) or
  `snapshot − (paths currently in the rectangle)` (unmark mode) fresh from
  the drag-start snapshot — so shrinking the rectangle back always restores
  whatever was marked before the drag, same reversibility the earlier
  toggle/XOR version had, just without toggling individual cells. Starting
  on empty space always means mark mode (there's no origin cell to read a
  mode from). `Ctrl`+drag isn't used for selection at all (reserved for the
  OS's usual "copy" D&D connotation).
- **Visual**: the cursor's row/tile gets its own highlight (a background tint
  plus an outline, reusing `AppColors.accent`/`bgHoverStrong`) independent of
  the mark's highlight, so cursor-only, mark-only, and both-at-once are all
  visually distinguishable — previously only marks were painted, so arrow-key
  navigation with nothing marked was invisible.
- **dired-style single-letter commands** (`m`/`u`/`t`/`Shift+u`/`Shift+c`/
  `Shift+r`/`Shift+d`): mark/unmark-and-advance, invert selection, deselect
  all, copy/move to the other pane (same as `F5`/`F6`), delete. These
  repurpose the existing "Type-ahead jump" setting (Preferences → General) as
  a mode switch rather than adding a new one: **on** (the original default)
  keeps today's first-letter-jump-to-file behavior for every letter; **off**
  disables that jump entirely and turns on these seven commands instead —
  avoids the two features permanently fighting over the same keys.
  `Shift+r` specifically checks the mark count: exactly one (or none) does an
  in-place rename (same as `F2`), two or more does the `F6` move-to-other-pane
  — a single rename target doesn't have an "other pane" destination that
  makes sense.
- Fixed along the way: the copy/move confirmation dialog said "Move
  \"x\" *here*?" with no indication of where "here" was — fine for a
  drag-and-drop drop (you can see the drop point) but meaningless for a
  keyboard-triggered `F5`/`F6`/dired transfer. Now shows the actual
  destination path. Also fixed: `deselectAll()` (bound to `Esc` and
  `Shift+u`) and `closeSearch()` both reset the cursor position to "none" as
  a side effect, even though neither actually changes what's in the list —
  the next arrow press after either would jump to the very start/end of the
  list instead of stepping from wherever the cursor visibly was.

Relevant commits: `64a9187`, `efa780a`.

## Runtime-switchable keyboard/mouse selection scheme

Preferences → General → "Keyboard & Mouse" → "Keyboard & mouse selection
scheme" switches the file list between the personal redesign above and a
faithful reproduction of `origin/main`'s original anchor-based model —
useful for comparing the two, or just falling back if the redesign ever
gets in the way. Takes effect after restarting Waydir (changing it shows a
toast saying so); a live switch would need every relevant method threaded
with a scheme check, which is a real ongoing maintenance cost for no benefit
over "pick a mode and restart."

- `SelectionController` is now an abstract base with two concrete
  implementations, `PersonalSelectionController` and
  `UpstreamSelectionController`, chosen once when `NavigationStore`
  constructs its controller. `UpstreamSelectionController` is ported
  near-verbatim from `git show origin/main:lib/features/navigation/selection_controller.dart`,
  including its quirks — e.g. `_applyCursorMove` reads `HardwareKeyboard`
  directly instead of the app's own `AppShortcuts` modifier helpers (an
  existing upstream inconsistency, not "fixed" here since the whole point
  is fidelity), and a Shift+move that extends the selection from an
  *unmarked* cursor cell can grow the mark set without actually moving the
  cursor (upstream returns from inside a `batch()` before reaching the
  `cursorIndex.value = next` line in that specific case).
- The `anchorIndex` signal the original redesign removed is back on
  `NavigationStore`/`SearchController`, unconditionally maintained
  alongside `cursorIndex` everywhere it used to be — harmless under the
  personal scheme (nothing reads it), required under upstream's. The one
  exception is `closeSearch()`: upstream resets the cursor to "none" there,
  but the personal scheme deliberately doesn't (a fixed bug, see above), so
  that one specific reset stays scheme-gated instead of unconditional.
- `RubberBandLayer` also branches per-scheme (checked once at build, not
  read live): upstream's drag can't start on top of a row and has no
  Shift requirement at all, reading Ctrl at fire-time for additive-vs-replace
  against the live rectangle; the personal scheme keeps its Shift-gated,
  snapshot-based paint model.
- dired commands (`m`/`u`/`t`/etc.) and the type-ahead-setting gating that
  gives them a keyboard slot are unaffected by this toggle — they work the
  same regardless of which arrow-key scheme is active.

Relevant commit: `281790b`.

## Quick Look: cursor vs. marked targeting, tree view arrow-key expand/collapse

Quick Look used to decide what to show from an inconsistent mix of the
marked selection and the cursor position (marks took priority for "2+
marked" and "1 marked folder", silently falling back to the cursor
otherwise) — confusing under the anchor-free cursor/mark model above, where
the cursor and the marks can legitimately point at different rows.

- **Space** always previews whatever the cursor is on, regardless of marks.
- **Shift+Space** previews the marked selection instead (one marked file
  shows that file; 2+ shows the multi-file properties view); a no-op with
  nothing marked.
- Either key also closes Quick Look while it's already open (previously
  only plain Space did).
- Right-click "Properties" is unaffected — still selection-based, now via
  an explicit `useMarkedSelection` flag on `showQuickLook` instead of
  relying on the same implicit priority Space/Shift+Space used to share.

Tree view (`fileViewMode: 'tree'`) also gained the standard VSCode/Explorer
arrow convention, alongside the existing `Ctrl+Enter` toggle
(`toggleTreeCursorFolder`): **Right** expands a collapsed folder at the
cursor, or — if already expanded — moves the cursor down into its first
child; **Left** collapses an expanded folder, or — if already collapsed, or
the cursor is on a file — moves the cursor up to its parent folder.

Found and fixed while testing the above: `NavigationStore.cursorEntry` read
the flat, non-tree `visibleFiles` list directly instead of the tree-aware
`_selectionFiles` getter every other cursor-consuming path already used
(the tree's own visual highlight, `SelectionController`). Harmless while
Quick Look mostly targeted marks, but once Space always targets the
cursor, opening Quick Look in tree view with any folder expanded could show
a completely unrelated file — `cursorIndex` was being read against two
different lists (the flat top-level list vs. the tree's flattened rows)
depending on which code path touched it.

Relevant commit: `94334d0`.

## Mouse click model: click moves the cursor, Ctrl+click marks

Plain click no longer toggles a mark at all — it's now the mouse equivalent
of an arrow key, moving only the cursor and leaving every mark untouched.
Ctrl+click takes over the old plain-click behavior (toggle the clicked
item's mark in place).

This was a deliberate follow-up after living with the original click-toggles
model: a first click most often means "look at this," not "mark this," and
having it move the cursor only — consistent with every keyboard cursor
move — turned out to feel more natural than the original toggle. Right-click
and dired commands (`m`/`u`/`t`/etc.) are unaffected.

**Shift+click: anchored range end.** Shift+click was first made a no-op (the
zero-drag case of Shift+drag's rubber band), which turned out unintuitive —
it should mean "end of a range". It now works like Explorer's, but in the
same paint style as Shift+arrow and Shift+drag:

- The first Shift+click of a session fixes the origin at the cursor and
  snapshots the marks; mark vs. unmark is decided once, from the origin
  cell. The range is inclusive of both ends, and the cursor moves to the
  clicked item.
- Each further Shift+click recomputes `snapshot ∪ [origin..click]` (or `−`
  when unmarking) from that snapshot, so overshooting and then Shift+clicking
  back toward the origin shrinks the range and restores what was outside it.
- The session ends on anything else that changes the cursor or the marks (a
  plain click, an arrow key, ...) — detected by checking the marks and cursor
  are still exactly what the last Shift+click left, rather than hooking every
  method — so the next Shift+click starts from wherever the cursor is.
- Shift+drag's rubber band is unchanged: a drag never fires the row's tap.

**Hover highlight yields to the keyboard.** In the list, grid and tree views,
the mouse-hover highlight looked too much like the keyboard cursor, especially
when the list scrolls under a stationary pointer. Any non-modifier key now
hides it, and real pointer movement brings it back (`PointerHoverStore`,
listening globally via `HardwareKeyboard` and a pointer-router global route).
Modifier keys don't count, so holding Shift for a Shift+click keeps the
highlight.

Also fixed: tree view's Left (ascend to the parent folder) went through
`jumpToIndex`, which in the personal scheme replaces the marks with the
target — so it wiped your marks. It now only moves the cursor.

Relevant commits: `5ec5722`, `3637e0b`.

## Grid thumbnails preserve aspect ratio

Both image thumbnails and generator-produced thumbnails in the file grid
used `BoxFit.cover` inside a fixed square tile, center-cropping anything
that wasn't already square. Switched to `BoxFit.contain` — but that alone
wasn't enough: `cacheWidth`/`cacheHeight` were both set to the same square
value, which forces `Image`'s decoder to squish the source to that exact
(non-aspect-preserving) pixel size *before* `fit` ever gets a chance to lay
it out, so the image would still look distorted despite `contain`. Fixed by
dropping `cacheHeight` and keeping only `cacheWidth` as a decode-size cap —
letting the decoder scale the other axis proportionally, preserving the
source's real aspect ratio all the way through.

Relevant commit: `e9af4e5`.

## Resize edges no longer swallow scrollbars

The widened resize hit areas (`bf84058`, above) overlapped the vertical
scrollbars sitting flush against the same edges, so grabbing a scrollbar
near a boundary often started a resize instead. Three separate edges, three
different fixes:

- **Dual-pane divider** (`PaneDivider`): its 18px hit area was centered on
  the boundary, reaching 9px into the left pane — fully covering that
  pane's 6px scrollbar gutter, and since the divider is the topmost `Stack`
  child with an opaque hit-test, the scrollbar underneath never saw the
  pointer. The reach is now asymmetric: 0px into the left pane, all 18px
  into the right pane (which has no scrollbar near its left edge), so the
  total grab width is unchanged.
- **Sidebar resize handle**: its whole hit area sits on the sidebar's own
  side, right over the sidebar's scrollbar, and it lives in a local `Stack`
  inside the `Row`'s sidebar slot, so it can't reach into the pane area the
  way the divider does without lifting its drag state up a level. Narrowed
  from 16px to 4px instead.
- **Window's left/right outer edges**: these are resolved natively
  (`WM_NCHITTEST` in `windows/runner/window/window.cpp`) before Flutter
  ever sees the click, so no Flutter-side change can let a scrollbar win.
  Rather than narrowing the margin's width (a compromise that still
  partially overlaps), the left/right straight edges now only resize when
  the cursor is level with the fixed-height, scrollbar-free chrome: the top
  100px (title bar 32 + tab strip 30 + location bar 38) or the bottom 22px
  (status bar). In between — the file list body, where scrollbars live —
  the click falls through to Flutter. Corners and top/bottom edges are
  unchanged. Those heights are hardcoded in the C++ to mirror the Dart
  widgets, so they need updating if those bars' heights ever change.
- Found while doing this: the native file must stay pure ASCII — an em dash
  in a comment tripped MSVC's C4819 (code page 932) warning, which this
  build treats as an error.

Relevant commit: `aac3153`.

## Right pane survives toggling dual-pane mode

Turning dual-pane mode off (`F9`) used to dispose the right pane outright,
and turning it back on created a fresh one at the left pane's current path —
losing its tabs, history, selection and scroll position every time. The
right `PaneStore` is now parked instead of disposed and reused on the next
`enterDual()`, so it comes back exactly as it was. This also applies when
dual-pane mode is entered implicitly (opening in, or moving a tab to, the
other pane): the new tab joins the right pane's existing tabs.

The parked pane is also included in session persistence, so restarting
while in single-pane mode keeps the right pane's tabs too (paths only, like
every restored tab — not history or selection). On restore, saved right-pane
tabs with dual-pane mode off are parked rather than loaded into the visible
pane list. A parked pane keeps watching its folders, same as when it's
visible.

Relevant commit: `9d35bd0`.

## Grid thumbnails in SFTP folders (per-tab toggle)

Remote folders never showed grid thumbnails (each one costs network
traffic). They can now be turned on per tab, on demand: **View → Remote
Thumbnails (This Tab)**, the command palette, or the tab's own right-click
menu (only shown on `sftp://` tabs, and toggles that tab even if it isn't
active). It's a `remoteThumbnails` signal on the tab's `NavigationStore` —
not persisted, so new tabs and restarts start with it off.

- **Images**: downloaded by a new `RemoteThumbnailCache` into the
  generator cache folder (so they survive across tabs and restarts, and
  are wiped by the generators "Reload" button like the rest of that
  cache). Up to 20 MB per file, at most 2 at a time.
- **Generators**: get the `sftp://user@host:port/...` URI as `%INPUT%`,
  exactly as Quick Look already did. Found while doing this: Quick Look's
  video previews over SFTP were already working — scoop's ffmpeg is built
  with libssh, reads `sftp://` URLs itself (authenticating with its own
  keys/agent, not Waydir's session) and fetches only the byte ranges it
  needs. Tools without sftp support (mutool, resvg, f3d, PowerShell)
  fall back to the icon.
- SFTP reads are synchronous FFI calls (`block_on` in Rust), so calling
  them on the UI isolate would freeze the UI once per image. The download
  runs in a background isolate instead, and in 1 MB range reads: the Rust
  side holds the session lock for the whole of each read, so one big read
  would make the UI's own SFTP listing calls wait behind it.
- `_GeneratorThumbnail` became a generic `_ResolvedThumbnail` (settle
  delay, `didUpdateWidget` identity reset) fed by either resolver, and the
  generator runner's process gate moved to `lib/utils/concurrency_gate.dart`
  so the downloads can reuse it.

Relevant commit: `e392516`.

## Quick Look audio playback

Revised the "no playback, ever" stance from preview generators (above): Quick
Look still won't draw a video's picture, but audio has no picture to draw in
the first place, so it's in scope. A `"time"`-paging generator's file now
auto-plays through an external command while browsing, muted videos excepted.

- Opt-in, like the diff command: add `player.json` to the same application
  support directory as `generators/` and `compare_diff.json`. No file, no
  playback — there's no sensible universal default the way `diff -y` was for
  the diff command. `cmd`/`args` with `%INPUT%`/`%START%` placeholders
  (absolute `HH:MM:SS.mmm` seek position, the same format `%SEEK%` already
  uses for generator pages), e.g. `ffplay -nodisp -vn -autoexit -nostats
  -loglevel quiet -volume 50 -ss %START% %INPUT%`.
- Eligibility: the cursor's file needs a matching generator paging by
  `"time"` (so PDF-style `"discrete"` paging never plays anything) *and* an
  actual audio stream — a quick dedicated `ffprobe` check, cached per file,
  keeps a muted video silent instead of spawning a player that has nothing to
  play.
- Autoplay while browsing, no pause state: moving the cursor restarts
  playback after a 250ms dwell (prevents chopped audio while flicking through
  files with the key held down); moving to anything non-playable — or a
  compare-mode diff appearing — kills the old process immediately, no wait.
  `PageUp`/`PageDown` re-seeks after a 100ms debounce, from either the
  keyboard handler or the on-screen page buttons (`GeneratorPageController`
  gained an `onManualChange` hook so both go through the same path). Playing
  through to the last page stops rather than looping.
- The shown page advances on its own from elapsed wall-clock time
  (`Timer.periodic`, 300ms) without restarting the player process — just
  swaps which cached frame `GeneratorPreview` displays, same as a user
  flipping pages manually.
- Stops the moment Waydir loses focus or is minimized
  (`WidgetsBindingObserver.didChangeAppLifecycleState`) and never
  auto-resumes on its own — regaining focus needs an actual cursor/page move,
  same as any other restart. Decided this way on the reasoning that anything
  meant to keep playing in the background belongs in a real media player, not
  Quick Look's browse-with-sound preview.
- No extra work needed for SFTP: `entry.realPath` for a remote file is
  already an `sftp://...` URI (see the grid-thumbnails entry above) and
  ffplay is the same libssh-enabled ffmpeg build already reading those for
  video thumbnails, so it should read them the same way.
- Installed locally: `player.json` running `ffplay` — not committed, same
  reasoning as generator config (local/personal, full-privileges trust
  model).
