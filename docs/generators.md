# Waydir Preview Generator Guide

Preview generators let Quick Look show a raster preview for file types Waydir has no built-in renderer for, by delegating the conversion to an external command you configure. Waydir never needs to understand the file format itself — it just runs your command and shows whatever image comes out.

A configured generator always takes priority over Waydir's built-in previews (images, PDF, Markdown) for the extensions it claims — adding one is a deliberate, explicit choice to handle that extension your own way, so it wins even where a built-in would otherwise apply.

## Where Config Lives

Generators are loaded from `.json` files in the `generators` folder inside Waydir's application support directory (the same place custom themes live, next to it):

- Linux: `$XDG_CONFIG_HOME/waydir/generators/` (or `~/.config/waydir/generators/`)
- Windows: `%APPDATA%\Waydir\generators\`
- macOS: `~/Library/Application Support/Waydir/generators/`

One file per generator, any filename, `.json` extension. Reloaded on startup.

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
| `outputExt` | no | Extension of the generated image file. Default `png`. |
| `paging` | no | `"time"` or `"discrete"` — see [Paging](#paging). Omit for a single, fixed preview. |
| `pageCount` | required for `paging: "time"` | Fixed number of evenly-spaced samples across the file. Ignored for `"discrete"` (the page count there comes from `probeCmd` instead, since it's file-specific). |
| `probeCmd` / `probeArgs` | required whenever `paging` is set | A command that prints a plain number to stdout — a duration in seconds for `"time"`, a page/unit count for `"discrete"`. |
| `probePattern` | no | Regex to pull that number out of `probeCmd`'s output when it isn't already a bare number (first capture group, or the whole match if the pattern has none). |

## Placeholders

Substituted in every element of `args`:

- `%INPUT%` — the source file's real path.
- `%OUTPUT%` — where to write the resulting image. Must end up with an extension matching `outputExt` — some tools (ffmpeg included) infer the output format from the filename extension, so a mismatched or missing extension makes the command fail even though nothing else is wrong.
- `%CACHE%` — the generator cache directory, if a command needs a scratch/working directory.
- `%SEEK%` — only meaningful for `paging: "time"`: the timestamp for the current page, as `HH:MM:SS.mmm`.
- `%POSITION%` — the current page as a 0-based integer (`0` when not paging).
- `%PAGE%` — the current page as a 1-based integer, for tools that count pages starting at 1 (e.g. `mutool draw`, `pdftoppm -f`/`-l`).

`%INPUT%` is also substituted in `probeArgs` (nothing else is — a probe only needs to read the file).

## Paging

Quick Look shows prev/next controls and a page indicator over a paged preview; each page is generated and cached independently, on demand, the first time it's viewed. `PageUp`/`PageDown` step through pages too, whenever a paged generator is the active preview (otherwise they scroll content as usual). There are two paging modes, depending on whether "page" means a point in time or a real per-file unit:

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

Waydir intentionally stops at paging through still frames — a scrubber or playback controls are a job for an embedded video player, not Quick Look.

## Caching

Results are cached by a hash of the file's path, size and modified time, plus the generator's own id, command and page — so editing the source file invalidates the cache automatically, and changing the generator's command (e.g. upgrading a tool, tweaking flags) invalidates it too without needing to touch the file itself.

## Failure Handling

Every failure mode falls back to Waydir's default file icon — a broken or missing generator never blocks Quick Look:

- Non-zero exit code → fallback, warning logged.
- Timeout → the process is killed, fallback, warning logged.
- Missing executable → fallback, warning logged.
- Zero exit but no output file produced → fallback, silent.

Check `Help → View Logs` (or the log file directly) for the exact command failure when a generator isn't producing output.

## Trust And Security

This works exactly like Waydir's Lua plugins: **generators run with your full user privileges and can execute any command.** Only add a generator you wrote yourself or trust completely.

Generator config is only ever loaded from your local application support directory — never from the folder you're currently browsing, and never automatically from a shared or synced location. If you version-control or share your generator configs, treat that the same as sharing a shell rc file: whoever runs it is trusting its contents completely.
