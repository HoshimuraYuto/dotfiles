# AGENTS.md

## Adding something new

Anything new under `claude/` that depends on a tool `install.sh` does not
install → add it to the Requirements table in `claude/README.md`.

`install.sh` symlinks `claude/rules/` as a directory and each `claude/skills/*`
individually. A new rule file is picked up with no further step; a new skill
directory needs `install.sh` re-run.
