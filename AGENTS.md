# AGENTS.md

## Adding something new

Anything new under `claude/` that depends on a tool `install.sh` does not
install → add it to the Requirements table in `claude/README.md`.

`install.sh` symlinks `claude/rules/` as a directory and each `claude/skills/*`
individually. A new rule file is picked up with no further step; a new skill
directory needs `install.sh` re-run.

A skill from another repository is not vendored here. List it in
`claude/external-skills.txt` with a pinned ref and `install.sh` installs it
globally. Whether it stays model-invocable is a separate decision, made with
`skillOverrides` in `claude/settings.json`.
