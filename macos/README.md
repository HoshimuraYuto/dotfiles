# macOS

Installs the packages in [`Brewfile`](Brewfile) with `brew bundle`.

```sh
./macos/install.sh -n # list missing packages
./macos/install.sh
```

Packages already installed but not listed are left alone.

## Requirements

Installed separately, not by `install.sh`.

|          | Used by      |
| -------- | ------------ |
| Homebrew | `install.sh` |
