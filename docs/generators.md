# Waydir Preview Generator Guide

Preview generators let Quick Look show a raster preview for file types Waydir has no built-in renderer for, by delegating the conversion to an external command you configure. Waydir never needs to understand the file format itself — it just runs your command and shows whatever image comes out. A generator can also produce plain text instead, such as an archive's file list; see [Text Output](#text-output).

A configured generator always takes priority over Waydir's built-in previews (images, PDF, Markdown) for the extensions it claims — adding one is a deliberate, explicit choice to handle that extension your own way, so it wins even where a built-in would otherwise apply.

The file grid also shows a generator's output as a thumbnail (always on, no separate setting) for any matching file, using the first page/frame only — the same cached image Quick Look uses, unless `thumbnailArgs` says otherwise (see [Config Format](#config-format)). This is throttled app-wide so scrolling through a folder full of matching files doesn't spawn a burst of helper processes at once, and a file whose generator fails isn't retried on every scroll back into view.

## Remote (SFTP) Files

For a file in an `sftp://` folder, `%INPUT%` is the `sftp://user@host:port/path` URI itself — Waydir doesn't download the file first. So a generator only works remotely if its tool can read `sftp://` URLs directly, authenticating on its own (SSH keys or an agent; Waydir's own login isn't shared with it). `ffmpeg` builds with libssh can, and only fetch the byte ranges they actually need; `mutool` and `resvg` can't, so those fall back to the file icon on remote files.

Grid thumbnails in remote folders are off by default, since each one costs network traffic. Turn them on per tab with **View → Remote Thumbnails (This Tab)** (or the command palette) — it lasts for that tab only and isn't saved. Remote image thumbnails are downloaded in the background (files up to 20 MB) and cached alongside generator output.

## Where Config Lives

Generators are loaded from `.json` files in the `generators` folder inside Waydir's application support directory (the same place custom themes live, next to it). The exact path is shown live in **Preferences → Quick Look → Preview generators** (the safest way to find it, since it can't drift out of sync with the app the way a hardcoded path in this doc can) — as of writing:

- Linux: `$XDG_CONFIG_HOME/waydir/generators/` (or `~/.config/waydir/generators/`)
- Windows: `%APPDATA%\dev.waydir\Waydir\generators\` — note the `dev.waydir\` segment (the app's configured `CompanyName`, `windows/runner/Runner.rc`), easy to miss if you're constructing the path by hand instead of copying it from Preferences.
- macOS: `~/Library/Application Support/Waydir/generators/`, though this may also nest under the app's bundle identifier (`dev.waydir.app`) depending on how `path_provider` resolves it on macOS — unverified, check Preferences for the actual path.

One file per generator, any filename, `.json` extension. Reloaded on
startup — or on demand from **Preferences → Quick Look → Preview
generators**, which also lets you add/edit/delete generators without
leaving the app.

## Worked Examples

[`docs/examples/generators/`](examples/generators/) has a ready-to-copy config for every generator this fork actually uses, one subfolder per id. Copy a subfolder's file(s) into your own generators folder (shown live in Preferences, above) and it works as-is — except a `<PLACEHOLDER>`-style token in `cmd`/`args`, called out in that file's own `_help`, which means the referenced tool or path is personal/private and needs pointing at your own copy first.

Cross-platform as one file (same tool, same CLI, on every OS it's installed on): `video-thumbnail` (ffmpeg), `pdf-page` (mutool), `audio-waveform` (ffmpeg), `3d-model`/`3d-model-iges`/`3d-model-step` (F3D — Windows additionally pages through a 10-step turntable via `%ANGLE%`, Linux/macOS renders one fixed angle; swap either way freely, both are valid).

Split into `<id>.windows.json` / `<id>.linux-macos.json` because the approach genuinely differs per OS:

| Generator | Windows | Linux/macOS |
|---|---|---|
| `svg-preview` | `resvg` | `rendersvg` (some distros package the same tool under this name — check which one you actually have) |
| `office-thumbnail` | PowerShell + .NET `ZipFile` | `sh` + `unzip -p` |
| `comsol-mph` | PowerShell + .NET `ZipFile` | `sh` + `unzip -p` |
| `ico-preview` | netpng's `ico2png` via a small PowerShell script that saves its stdout (`<GENERATORS_DIR>` placeholder) | netpng's `ico2png` (github.com/tsnomura/netpng, on PATH) via `sh -c` |
| `font-preview` | GDI+/WPF (see [Multi-File Generators](#multi-file-generators) below) | none — Windows-only API |
| `archive-list` | 7-Zip's `7z l` (text output, see [Text Output](#text-output)) for zip/7z/rar/zst/cab/iso/jar | libarchive's `bsdtar -tvf`, tarballs included |
| `tar-list` | Git for Windows' GNU tar for tar/tgz/gz/bz2/xz (7z would only show a `.tar.gz`'s inner `.tar`) | none — `archive-list` covers tarballs |

The Linux/macOS `sh` scripts pass `%INPUT%`/`%OUTPUT%` as `$1`/`$2` (real argv entries after a `sh` placeholder for `$0`) instead of substituting them into the script text — the same fix `font-preview` applies on the PowerShell side: a path containing a single quote (or any other shell-special character) can't break the script's own quoting, because it's never textually inside it to begin with.

Preferences only edits the simple scalar fields (`id`, `extensions`, `cmd`,
`timeoutSeconds`, `outputExt`) through a small form; `args`, paging and
probe settings still need hand-editing the JSON (an "Edit JSON" button
opens the file in your default editor). A generator added through
Preferences starts with empty `args`, so fill those in via "Edit JSON"
before it does anything useful.

## Config Format

```json
{
  "id": "video-thumbnail",
  "extensions": ["mp4", "mkv", "mov", "avi", "webm", "m4v"],
  "cmd": "ffmpeg",
  "args": ["-y", "-ss", "00:00:01", "-i", "%INPUT%", "-frames:v", "1", "-vf", "scale=640:-1", "%OUTPUT%"],
  "timeoutSeconds": 8,
  "outputExt": "png"
}
```

| Field | Required | Description |
|---|---|---|
| `id` | yes | Unique name, used in logs and cache keys. |
| `extensions` | yes | Lowercase extensions (no dot) this generator handles. |
| `cmd` | yes | Executable to run. Must be resolvable on `PATH` or an absolute path. |
| `args` | yes | Argument list passed directly to the process — no shell involved, so no quoting or injection concerns. |
| `timeoutSeconds` | no | Default 8, clamped to a maximum of 60. The process is killed if it runs longer. Also applies to `probeCmd`. |
| `outputExt` | no | Extension of the generated image file. Default `png`. `txt` makes the output text instead of an image; see [Text Output](#text-output). |
| `textFrom` | no | Text output only: a regex for the first line to show. Lines above the first matching line (a tool's banner, say) are dropped; no match shows everything. |
| `stdout` | no | `true` saves the command's stdout as the output file, byte for byte, for tools that print their result instead of writing a file. `%OUTPUT%` is then usually left out of `args`. Default `false`. |
| `paging` | no | `"time"`, `"discrete"` or `"fixed"` — see [Paging](#paging). Omit for a single, fixed preview. |
| `pageCount` | required for `paging: "time"` and `"fixed"` | Fixed number of pages (> 1): evenly-spaced samples across the file for `"time"`, a plain page count for `"fixed"`. Ignored for `"discrete"` (the page count there comes from `probeCmd` instead, since it's file-specific). |
| `probeCmd` / `probeArgs` | required for `paging: "time"` and `"discrete"` | A command that prints a plain number to stdout — a duration in seconds for `"time"`, a page/unit count for `"discrete"`. |
| `probePattern` | no | Regex to pull that number out of `probeCmd`'s output when it isn't already a bare number (first capture group, or the whole match if the pattern has none). |
| `thumbnailArgs` | no | Overrides `args` for the file grid's thumbnail only — Quick Look always uses `args`. A separate cache entry from page 0 of `args`, so it doesn't have to be the same kind of image at all; see [Separate Thumbnail](#separate-thumbnail). |

## Placeholders

Substituted in every element of `args`:

- `%INPUT%` — the source file's real path.
- `%OUTPUT%` — where to write the resulting image. Must end up with an extension matching `outputExt` — some tools (ffmpeg included) infer the output format from the filename extension, so a mismatched or missing extension makes the command fail even though nothing else is wrong.
- `%CACHE%` — the generator cache directory, if a command needs a scratch/working directory.
- `%SEEK%` — only meaningful for `paging: "time"`: the timestamp for the current page, as `HH:MM:SS.mmm`.
- `%POSITION%` — the current page as a 0-based integer (`0` when not paging).
- `%PAGE%` — the current page as a 1-based integer, for tools that count pages starting at 1 (e.g. `mutool draw`, `pdftoppm -f`/`-l`).
- `%ANGLE%` — a full turn split across the pages: `360 × position ÷ pageCount` degrees (`0`, `36`, `72` … `324` for 10 pages; up to 3 decimals when it doesn't divide evenly, `0` when not paging). Meant for `paging: "fixed"` turntable previews.

`%INPUT%` is also substituted in `probeArgs` (nothing else is — a probe only needs to read the file).

## Paging

Quick Look shows prev/next controls and a page indicator over a paged preview. Opening Quick Look on a paged file starts generating every page in the background, one at a time, so paging forward is usually instant by the time you get there instead of waiting on ffmpeg/mutool per page; this stops if you close Quick Look or move to a different file before it finishes. `PageUp`/`PageDown` step through pages too, whenever a paged generator is the active preview (otherwise they scroll content as usual). There are three paging modes, depending on whether "page" means a point in time, a real per-file unit, or just a fixed number of views:

**`"time"`** — a fixed `pageCount` of evenly-spaced samples across the file's duration, from 0% up to but excluding 100% (decoders can't extract a frame at the exact end of a file). `probeCmd` reports the duration in seconds, used to compute `%SEEK%`:

```json
{
  "id": "video-thumbnail",
  "extensions": ["mp4", "mkv", "mov", "avi", "webm", "m4v"],
  "cmd": "ffmpeg",
  "args": ["-y", "-ss", "%SEEK%", "-i", "%INPUT%", "-frames:v", "1", "-vf", "scale=640:-1", "%OUTPUT%"],
  "paging": "time",
  "pageCount": 10,
  "probeCmd": "ffprobe",
  "probeArgs": ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", "%INPUT%"],
  "timeoutSeconds": 8
}
```

**`"discrete"`** — a source with a real, file-specific unit count, like a PDF's page count. There's no fixed `pageCount` in config since it varies per file; `probeCmd` reports the file's own count instead, and `%PAGE%`/`%POSITION%` select which one to render:

```json
{
  "id": "pdf-page",
  "extensions": ["pdf"],
  "cmd": "mutool",
  "args": ["draw", "-o", "%OUTPUT%", "%INPUT%", "%PAGE%"],
  "paging": "discrete",
  "probeCmd": "mutool",
  "probeArgs": ["info", "%INPUT%"],
  "probePattern": "Pages:\\s*(\\d+)",
  "timeoutSeconds": 8
}
```

(`mutool info` prints several lines of metadata, including `Pages: N` — `probePattern` pulls just the number out of it. `mutool draw -o <exact-path> file.pdf <page>` renders straight to the given filename with no page-number suffix, matching `%OUTPUT%`'s contract; poppler's `pdftoppm` always appends its own suffix to the output prefix, which doesn't fit that contract without extra handling, so `mutool` is the simpler fit here despite `pdftoppm`/`pdfinfo` also being common.)

**`"fixed"`** — a fixed `pageCount` of pages with nothing read from the file, so no `probeCmd`. Combine it with `%ANGLE%` (or `%POSITION%`/`%PAGE%`) to render different views of the same file, e.g. a 3D model turning around its Z axis with [F3D](https://f3d.app):

```json
{
  "id": "3d-model",
  "extensions": ["stl", "obj", "ply", "3mf"],
  "cmd": "f3d",
  "args": ["%INPUT%", "--output=%OUTPUT%", "--resolution=640,480", "--no-config",
           "--up=+Z", "--camera-azimuth-angle=%ANGLE%", "--camera-elevation-angle=25"],
  "paging": "fixed",
  "pageCount": 10,
  "timeoutSeconds": 30
}
```

(`--up=+Z` makes Z the up axis, so the azimuth turns the model around Z; models authored Y-up, such as glTF, lie on their side with it. Every page is a separate F3D run, cached like any other page.)

Waydir intentionally stops at paging through still frames — a scrubber or playback controls are a job for an embedded video player, not Quick Look.

## Separate Thumbnail

The grid tile and Quick Look normally show the exact same image (page 0 of `args`), which is fine for most generators — a video frame or a 3D model render both read fine shrunk down. Some previews don't: a type specimen with a full sample paragraph plus the font's family name is legible in Quick Look but just noise at tile size. `thumbnailArgs` swaps in a different command for the grid only, always a single static image regardless of `paging` — the grid never pages:

```json
{
  "id": "font-preview",
  "extensions": ["ttf", "otf", "ttc"],
  "cmd": "powershell",
  "args": ["-NoProfile", "-NonInteractive", "-Command", "<render a sample paragraph + family name>"],
  "paging": "fixed",
  "pageCount": 4,
  "thumbnailArgs": ["-NoProfile", "-NonInteractive", "-Command", "<render just two glyphs, nothing else>"]
}
```

Omit it and the grid falls back to page 0 of `args` exactly as before — same cache entry, no extra work.

## Text Output

With `"outputExt": "txt"`, Quick Look shows the generator's output in its text view (read-only, monospace, scrollable, selectable and copyable) instead of as an image. It's decoded as UTF-8. This suits anything a command-line tool can describe in text: an archive's file list, media info from `ffprobe`, metadata from `exiftool`. Paging works the same as for images. The grid keeps the plain file icon, since there's no thumbnail to draw from text.

Most such tools print to stdout rather than writing a file, so pair it with `"stdout": true`:

```json
{
  "id": "archive-list",
  "extensions": ["zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz", "zst", "cab", "iso", "jar"],
  "cmd": "7z",
  "args": ["l", "-sccUTF-8", "-p", "%INPUT%"],
  "stdout": true,
  "textFrom": "^\\s*Date\\s+Time\\s+Attr",
  "timeoutSeconds": 15,
  "outputExt": "txt"
}
```

(`textFrom` starts the shown text at 7z's column header, dropping the copyright banner and archive properties printed above it; the cached output itself is untouched. `-sccUTF-8` makes 7-Zip print UTF-8 rather than the console code page. The empty `-p` keeps it from waiting for a password: an archive with encrypted file names fails at once, so Quick Look shows no preview, while one with only encrypted contents still lists. The Linux/macOS example uses `bsdtar -tvf %INPUT%` instead.)

`"stdout": true` works for images too: a converter that streams PNG to stdout can be used directly, no wrapper script needed.

## Multi-File Generators

`cmd`/`args` don't have to be an inline one-liner — once a generator has real logic, point `args` at a saved script instead (`-File <path>` rather than `-Command "<huge string>"`), and have it `.`-dot-source a shared helper file via `$PSScriptRoot` (PowerShell resolves that to the running script's own folder, so a sibling file works without a hardcoded path). `probeCmd`/`probeArgs` and `thumbnailArgs` can point at their own small scripts the same way, all sharing that one helper.

[`docs/examples/generators/font-preview/`](examples/generators/font-preview/) is a full worked example built this way: `font-preview-lib.ps1` (shared), `font-preview.ps1` (the paged Quick Look preview), `font-preview-count.ps1` (`probeCmd`, reporting a per-file page count via `"discrete"` paging), and `font-thumbnail.ps1` (`thumbnailArgs`). The shared library uses WPF's `GlyphTypeface` (`System.Windows.Media`, the `PresentationCore` assembly) to check which scripts a font actually has glyphs for — a Japanese-capable font gets a Japanese sample as page 1 and a kanji as its grid thumbnail instead of a fixed 'Ag', a Latin-only font never shows a blank/tofu Japanese page, and the page count itself varies per file since it's driven by `"discrete"` probing rather than a fixed `pageCount`. To use it: copy the four files into your generators folder, then edit `font-preview.json`'s three script paths (`<GENERATORS_DIR>` placeholders) to that same folder's real path before dropping it in alongside them.

## Caching

Results are cached by a hash of the file's path, size and modified time, plus the generator's own id, command and page — so editing the source file invalidates the cache automatically, and changing the generator's command (e.g. upgrading a tool, tweaking flags) invalidates it too without needing to touch the file itself.

## Failure Handling

Every failure mode falls back to Waydir's default file icon — a broken or missing generator never blocks Quick Look:

- Non-zero exit code → fallback, warning logged.
- Timeout → the process is killed, fallback, warning logged.
- Missing executable → fallback, warning logged.
- Zero exit but no output produced (no file, or an empty one — e.g. nothing printed with `"stdout": true`) → fallback, silent.

Check `Help → View Logs` (or the log file directly) for the exact command failure when a generator isn't producing output.

## Trust And Security

This works exactly like Waydir's Lua plugins: **generators run with your full user privileges and can execute any command.** Only add a generator you wrote yourself or trust completely.

Generator config is only ever loaded from your local application support directory — never from the folder you're currently browsing, and never automatically from a shared or synced location. If you version-control or share your generator configs, treat that the same as sharing a shell rc file: whoever runs it is trusting its contents completely.
