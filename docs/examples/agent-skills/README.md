# Agent skills

Skills that let a coding agent (Claude Code and other tools that read
`SKILL.md` skills) drive a running Waydir.

| Skill | What it does |
|---|---|
| [`waydir-show`](waydir-show/SKILL.md) | Shows a file or folder in Waydir: opens the folder in a new tab of the active pane with the cursor on the file. It uses the same signal file as the shell's `wd <path>`. |

## Install

Copy the skill's folder into your user skills directory:

```bash
cp -r docs/examples/agent-skills/waydir-show ~/.claude/skills/
```

```powershell
Copy-Item -Recurse docs\examples\agent-skills\waydir-show "$HOME\.claude\skills\"
```

Waydir must have run at least once, so that `WAYDIR_CWD_DIR` is set in
your environment.

### Codex CLI

Run the installer (after starting Waydir once):

```bash
bash docs/examples/agent-skills/install-codex.sh
```

It copies the skills to `~/.codex/skills/` (or `$CODEX_HOME/skills/`).
Codex's default `workspace-write` sandbox only allows writes inside the
workspace, so the installer also adds the Waydir signal directory to
`writable_roots` in `~/.codex/config.toml`. It keeps a `.bak` of the old
config, and running it again changes nothing. To do it by hand instead,
use your real absolute path (`~` and variables are not expanded):

```toml
[sandbox_workspace_write]
writable_roots = ["/home/<user>/.config/waydir/cwd_signals"]
```

Without this, the skill's write fails with "Read-only file system". Restart
Codex after changing the config.
