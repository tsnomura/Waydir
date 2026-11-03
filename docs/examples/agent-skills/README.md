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
