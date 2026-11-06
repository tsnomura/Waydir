# Send to terminal

Fills the marked items (or the cursor item) into a command template and
types the result into the built-in terminal of the active pane. Enter is
not pressed, so the command can be checked and edited before it runs.

Each `.json` file in the plugin folder, next to `init.lua`, is one entry
in the right-click **Send to terminal** submenu (`manifest.json` is the
plugin's own and is not a template). The file name without `.json` is the
entry's id, and entries are sorted by it. Add a template by adding a file; remove one you
don't need by deleting its file. Updating the plugin replaces the shipped
files only, so your own files stay.

```json
{
  "title": "rsync to the other pane",
  "command": "rsync -a -z --progress {paths} {dest}",
  "os": "unix"
}
```

## Fields

| Field | Meaning |
|-------|---------|
| `title` | Menu label. Required. |
| `command` | Command line with placeholders. Required unless `builder` is set. |
| `builder` | Use a built-in builder instead of `command`: `robocopy` or `scp`. |
| `flags` | Options passed to a builder. Defaults: robocopy `/MT:8 /Z` (folders also get `/E`), scp `-r -C`. |
| `each` | `true` fills `command` once per target and joins the results with `join`. |
| `join` | Separator for `each`. Defaults to ` && `. |
| `os` | `windows` or `unix`: the entry refuses to run on the other kind and shows a toast. |
| `quote` | `cmd` or `posix`. Defaults to `cmd` when a Windows path is involved, else `posix`. |
| `shell` | Shell to open the terminal with, e.g. `cmd.exe`. |
| `cwd` | Terminal folder. Defaults to the current folder; `~` is the home folder. |
| `when` | Selection filter, as in `waydir.register` (e.g. `{ "types": ["file"] }`). |

## Placeholders

| Placeholder | Value |
|-------------|-------|
| `{paths}` | Every target, quoted, separated by spaces. |
| `{dest}` | The other pane's folder (the current folder in single-pane mode), quoted. |
| `{dir}` | The current folder, quoted. |
| `{path}` | With `each`: the target, quoted. |
| `{name}` | With `each`: its file name, quoted. |
| `{parent}` | With `each`: its folder, quoted. |

## Builders

- `robocopy` copies each folder into a same-named folder under `{dest}`
  and groups loose files by their folder (robocopy takes one source folder
  per call), chained with `&&`.
- `scp` turns `sftp://user@host:port/path` into `user@host:/path` and adds
  `-P port` for a port other than 22. Use it with `"cwd": "~"`, since a
  terminal opened in an sftp folder is a shell on that host.
