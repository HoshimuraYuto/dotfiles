# Claude

`~/.claude/settings.json` is rewritten by external tools, so it cannot live in git. This directory's `settings.json` is loaded on top of it with `--settings`.

```
claude --settings ~/dotfiles/claude/settings.json
```

## Setup

Clone to `~/dotfiles` — `settings.json` points at `~/dotfiles/claude/statusline.sh`.

```
npm install          # git hooks
./claude/install.sh  # symlinks
```

## install.sh

Symlinks `rules/` to `~/.claude/rules/dotfiles`, and each `skills/*` into `~/.claude/skills/`.

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
