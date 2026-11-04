---
name: waydir-show
description: Show a file or folder to the user in their running Waydir file manager — opens the file's folder in a new tab of the active pane with the cursor on the file (a folder path just opens that folder). Use whenever the user asks to show, reveal, open or locate a file/folder "in Waydir" (Waydirで表示/開いて/見せて、ファイルの場所を開いて), or when pointing them at an output file you just produced would help and they use Waydir. Not for opening a file in its application.
---

# waydir-show

Waydir watches a signal directory; writing an absolute path into
`$WAYDIR_CWD_DIR/0.txt` makes the active pane open a new tab on it. For a
file, the tab opens the parent folder with the cursor on that file (no mark
is added).

## Where the signal directory is

`WAYDIR_CWD_DIR` is persisted by Waydir after its first run, but an agent's
non-interactive shell may not have it:

- Windows: a user environment variable, always readable from PowerShell
  with `[Environment]::GetEnvironmentVariable('WAYDIR_CWD_DIR', 'User')`.
  Default `%APPDATA%\dev.waydir\Waydir\cwd_signals`.
- Linux: exported by `<support dir>/env.sh`, which Waydir sources from
  `~/.bashrc`, `~/.profile` and similar. A non-interactive shell may not read
  those files. Fall back to the default
  `${XDG_CONFIG_HOME:-$HOME/.config}/waydir/cwd_signals`.
- macOS: also exported by `env.sh` in the app's support directory under
  `~/Library/Application Support/`. If the variable is unset, ask the user.

If the directory doesn't exist, Waydir has never run for this user. Say so
rather than creating it.

## How

Waydir deletes the signal file as soon as it reads it (after a 150 ms
debounce), so a file that is gone a second later means Waydir is running
and took the request. A file still there means Waydir is not running:
remove it and ask the user. Don't check for the process instead — inside a
sandbox (e.g. Codex CLI, which runs commands in its own PID namespace)
`pgrep`/`/proc` can't see Waydir even when it is running.

PowerShell (Windows):

```powershell
$dir = [Environment]::GetEnvironmentVariable('WAYDIR_CWD_DIR', 'User')
$path = (Resolve-Path -LiteralPath '<path>').ProviderPath
[IO.File]::WriteAllText("$dir\0.txt", $path)
Start-Sleep -Seconds 1
if (Test-Path "$dir\0.txt") { Remove-Item "$dir\0.txt"; 'Waydir is not running' } else { 'shown' }
```

Bash (Linux / macOS):

```bash
dir="${WAYDIR_CWD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/waydir/cwd_signals}"
realpath -- '<path>' > "$dir/0.txt"
sleep 1
if [ -e "$dir/0.txt" ]; then rm -f "$dir/0.txt"; echo 'Waydir is not running'; else echo shown; fi
```

Git Bash on Windows uses the Windows path form: `cygpath -wa '<path>'`
instead of `realpath`, and the directory from the PowerShell line above.

"shown" only means Waydir received the request; it silently ignores a path
that doesn't exist (see Rules).

## When the write is refused (Codex sandbox)

Codex CLI's `workspace-write` sandbox only lets commands write inside the
workspace, so the signal directory looks read-only ("Read-only file
system") even though the user owns it. The installer
(`docs/examples/agent-skills/install-codex.sh` in the Waydir repo) adds the
directory to the sandbox; if the write is still refused, it wasn't run or
Codex hasn't been restarted since. Don't try to get around
this. Tell the user to allow that one directory in `~/.codex/config.toml`,
using the expanded absolute path of the signal directory:

```toml
[sandbox_workspace_write]
writable_roots = ["/home/<user>/.config/waydir/cwd_signals"]
```

Codex picks it up after a restart. Until then, give the user the command to
run in their own terminal: `wd /absolute/path/to/file`. Don't edit the
Codex config yourself.

## Rules

- The path must exist and be absolute in native form (`C:\...` on Windows,
  `/...` on Linux/macOS; never `/c/...` MSYS form).
  Anything else is silently dropped — resolve relative paths first, as above.
- Id `0` targets the active pane. Showing several files means several tabs;
  prefer one call for the most relevant file, or the common folder.
- Nothing is reported back. Tell the user what you opened (full path), and
  mention that a hidden file only gets the cursor if hidden files are shown.
- A file argument needs a Waydir build with the `wd` path-argument feature
  (tsnomura/Waydir personal, PR #119, 2026-11). An older build ignores file
  paths; pass the parent folder instead if the user reports nothing happened.
- Waydir must be running. It reacts to file create/modify events only, so a
  request written while it is closed is not picked up at startup. That is
  why the snippets remove a file that wasn't taken, instead of leaving a
  stale request behind.
- If Waydir isn't running, never launch it yourself. Ask the user to start
  Waydir, and once they confirm, run the snippet again.
