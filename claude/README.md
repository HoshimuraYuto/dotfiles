# Claude

`~/.claude/settings.json` is rewritten by external tools, so it cannot live in git. This directory's `settings.json` is loaded on top of it with `--settings`.

```
claude --settings ~/dotfiles/claude/settings.json
```

## Setup

Clone to `~/dotfiles` — `settings.json` points at `~/dotfiles/claude/statusline.sh`.

```
./mise/install.sh    # Node, git hooks, skills CLI
./claude/install.sh  # symlinks, external skills
```

## install.sh

Symlinks `rules/` to `~/.claude/rules/dotfiles`, and each `skills/*` into
`~/.claude/skills/`. These skill entries and the common rule files link to the
root [`skills/`](../skills) and [`rules/`](../rules) sources. Existing links still
work through the additional symlink.

Skills listed in [`external-skills.txt`](../external-skills.txt) are installed
globally by the skills CLI, not vendored. An existing installation is retained;
after changing a pinned ref, reinstall that external skill at the new ref.
`CLAUDE_CONFIG_DIR` changes the link destination; external downloads still use
the CLI's global location and are linked into a custom destination if needed.

```
./claude/install.sh       # run
./claude/install.sh -n    # preview only
```

## Requirements

Installed separately, not by `install.sh`.

|               | Used by                                           |
| ------------- | ------------------------------------------------- |
| agent-browser | `rules/web-research.md`, shared `skills/context7` |
| jq            | `statusline.sh`, shared `skills/context7`         |
| Node          | `install.sh`, external `security-audit`           |
