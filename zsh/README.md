# zsh

Symlinks `.zprofile`, `.zshrc` and `.p10k.zsh` into `~`.

```sh
./zsh/install.sh -n # preview
./zsh/install.sh
```

Existing files are reported as conflicts, not replaced; move them aside first.
Put secrets and machine-specific settings in `~/.zshrc.local`, which `.zshrc`
sources if it exists.

## Requirements

Installed separately, not by `install.sh`.

|                                                    | Used by     |
| -------------------------------------------------- | ----------- |
| Homebrew (default prefix)                          | `.zprofile` |
| [`macos/Brewfile`](../macos/Brewfile) zsh packages | `.zshrc`    |
| [`macos/Brewfile`](../macos/Brewfile) `mise`       | `.zshrc`    |
