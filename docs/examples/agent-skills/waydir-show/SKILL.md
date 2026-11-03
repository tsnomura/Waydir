---
name: waydir-show
description: Show a file or folder to the user in their running Waydir file manager — opens the file's folder in a new tab of the active pane with the cursor on the file (a folder path just opens that folder). Use whenever the user asks to show, reveal, open or locate a file/folder "in Waydir" (Waydirで表示/開いて/見せて、ファイルの場所を開いて), or when pointing them at an output file you just produced would help and they use Waydir. Not for opening a file in its application.
---

# waydir-show

Waydir watches a signal directory; writing an absolute path into
`<WAYDIR_CWD_DIR>\0.txt` makes the active pane open a new tab on it. For a file,
the tab opens the parent folder with the cursor on that file (no mark is added).

## How

PowerShell (works from any project, no shell function needed):

```powershell
$dir = [Environment]::GetEnvironmentVariable('WAYDIR_CWD_DIR', 'User')
$path = (Resolve-Path -LiteralPath '<path>').ProviderPath
[IO.File]::WriteAllText("$dir\0.txt", $path)
```

Bash (Git Bash / Linux), equivalent to the user's `wd <path>` function:

```bash
cygpath -wa '<path>' > "$WAYDIR_CWD_DIR/0.txt"          # Git Bash on Windows
realpath -- '<path>' > "$WAYDIR_CWD_DIR/0.txt"          # Linux/macOS
```

If `WAYDIR_CWD_DIR` is unset, Waydir has never run on this machine/account;
tell the user rather than guessing a path. (On Windows it is normally
`%APPDATA%\dev.waydir\Waydir\cwd_signals`.)

## Rules

- The path must exist and be absolute in native form (`C:\...` on Windows).
  Anything else is silently dropped — resolve relative paths first, as above.
- Id `0` targets the active pane. Showing several files means several tabs;
  prefer one call for the most relevant file, or the common folder.
- Nothing is reported back. Tell the user what you opened (full path), and
  mention that a hidden file only gets the cursor if hidden files are shown.
- A file argument needs a Waydir build with the `wd` path-argument feature
  (tsnomura/Waydir personal, PR #119, 2026-11). An older build ignores file
  paths; pass the parent folder instead if the user reports nothing happened.
- Waydir must be running. It reacts to file create/modify events only, so a
  request written while it is closed is not picked up at startup (the file
  just sits there until the next write overwrites it). Check with
  `Get-Process waydir` first and tell the user if it isn't running.
