# Waydir Preview Generator Guide

Preview generators let Quick Look show a raster preview for file types Waydir has no built-in renderer for, by delegating the conversion to an external command you configure. Waydir never needs to understand the file format itself — it just runs your command and shows whatever image comes out.

Generators only fill gaps. They never take priority over Waydir's built-in previews (images, PDF, Markdown) — they only apply to extensions those don't already handle.

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
| `pageCount` | no | Number of pages Quick Look can step through for this file, for a timed source (e.g. video). Default 1 (single preview, no page controls shown). Requires `probeCmd`. |
| `probeCmd` / `probeArgs` | required if `pageCount` > 1 | A command that prints the source's duration in seconds (a plain number) to stdout — see [Paging](#paging). |

## Placeholders

Substituted in every element of `args`:

- `%INPUT%` — the source file's real path.
- `%OUTPUT%` — where to write the resulting image. Must end up with an extension matching `outputExt` — some tools (ffmpeg included) infer the output format from the filename extension, so a mismatched or missing extension makes the command fail even though nothing else is wrong.
- `%CACHE%` — the generator cache directory, if a command needs a scratch/working directory.
- `%SEEK%` — only meaningful when `pageCount` > 1: the timestamp for the current page, as `HH:MM:SS.mmm`.
- `%POSITION%` — only meaningful when `pageCount` > 1: the current page as a 0-based integer.

`%INPUT%` is also substituted in `probeArgs` (nothing else is — a probe only needs to read the file).

## Paging

A generator with `pageCount` > 1 samples `pageCount` evenly-spaced points across the file's duration, from 0% up to but excluding 100% (decoders can't extract a frame at the exact end of a file). Quick Look shows prev/next controls and a page indicator over the preview; each page is generated and cached independently, on demand, the first time it's viewed.

To compute `%SEEK%`, Waydir first runs `probeCmd`/`probeArgs` once per file (memoized for the app's lifetime) and parses its stdout as a number of seconds. Example using `ffprobe`:

```json
{
  "id": "video-thumbnail",
  "extensions": ["mp4", "mkv", "mov", "avi", "webm", "m4v"],
  "cmd": "ffmpeg",
  "args": ["-y", "-ss", "%SEEK%", "-i", "%INPUT%", "-frames:v", "1", "-vf", "scale=640:-1", "%OUTPUT%"],
  "pageCount": 10,
  "probeCmd": "ffprobe",
  "probeArgs": ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", "%INPUT%"],
  "timeoutSeconds": 8
}
```

A discretely-paginated source like a PDF or a slide deck doesn't need this at all — that's `%POSITION%` used directly as a page/slide index, with no `probeCmd` needed, since the page count is already known ahead of time (pass it as `pageCount` directly). `%SEEK%` only exists for sources where a page maps to a point in time rather than a fixed unit.

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
