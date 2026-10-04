# Dotfiles

Personal [Claude](claude/README.md) and [Codex](codex/README.md) configuration.

```sh
npm install
./claude/install.sh
./codex/install.sh
```

Use `-n` with either installer to preview changes. Existing files and unrelated
settings are preserved; conflicting entries are reported instead of replaced.

Shared skills live in `skills/`; each agent's `skills/` links to those sources.
Shared instructions live in `rules/`. External skills are listed with pinned
refs in `external-skills.txt` and installed globally, not vendored here.
