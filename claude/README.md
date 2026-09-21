# Claude

`~/.claude/settings.json` is rewritten by external tools, so it cannot live in git. This directory's `settings.json` is loaded on top of it with `--settings`.

```
claude --settings ~/dotfiles/claude/settings.json
```

## Setup

Clone to `~/dotfiles` — `settings.json` points at `~/dotfiles/claude/statusline.sh`.

```
npm install          # git hooks, skills CLI
./claude/install.sh  # symlinks, external skills
```

## install.sh

Symlinks `rules/` to `~/.claude/rules/dotfiles`, and each `skills/*` into `~/.claude/skills/`. Skills listed in `external-skills.txt` are installed into `~/.claude/skills/` instead of being symlinked.

```
./claude/install.sh       # run
./claude/install.sh -n    # preview only
```

## Requirements

Installed separately, not by `install.sh`.

|               | Used by                                    |
| ------------- | ------------------------------------------ |
| agent-browser | `rules/web-research.md`, `skills/context7` |
| jq            | `statusline.sh`, `skills/context7`         |
| Node          | `install.sh`                               |
