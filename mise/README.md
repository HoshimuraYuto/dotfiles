# mise

Symlinks [`config.toml`](config.toml) to `~/.config/mise/config.toml` and
installs the tools it lists with `mise install`, then runs `npm install` in the
repository for the git hooks and the skills CLI used by the other installers.

```sh
./mise/install.sh -n # preview
./mise/install.sh
```

An existing `config.toml` is reported as a conflict, not replaced, and nothing
is installed until it is resolved.

## Requirements

Installed separately, not by `install.sh`.

|                                              | Used by                    |
| -------------------------------------------- | -------------------------- |
| [`macos/Brewfile`](../macos/Brewfile) `mise` | `install.sh`, `zsh/.zshrc` |
