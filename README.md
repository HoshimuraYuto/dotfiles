# Dotfiles

Personal macOS setup: [Homebrew packages](macos/README.md), [zsh](zsh/README.md),
[git](git/README.md), [mise tools](mise/README.md), and [Claude](claude/README.md),
[Codex](codex/README.md) and [Hermes](hermes/README.md) configuration.

Install [Homebrew](https://brew.sh) first, then:

```sh
./macos/install.sh
./zsh/install.sh
./git/install.sh
./mise/install.sh
./claude/install.sh
./codex/install.sh
./hermes/install.sh
```

Use `-n` with any installer to preview changes. Existing files and unrelated
settings are preserved; conflicting entries are reported instead of replaced.

Shared skills live in `skills/`; each agent's `skills/` links to those sources.
Shared instructions live in `rules/`. External skills are listed with pinned
refs in `external-skills.txt` and installed globally, not vendored here.
