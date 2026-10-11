# git

Symlinks [`config`](config) and [`ignore`](ignore) into `~/.config/git/`.

```sh
./git/install.sh -n # preview
./git/install.sh
```

Existing files are reported as conflicts, not replaced; move them aside first.
Put `[user]` (`name`, `email`, `signingkey`) in `~/.gitconfig`, which git reads
after `~/.config/git/config`. Commits fail to sign until `signingkey` is set.

## Requirements

Installed separately, not by `install.sh`.

|              | Used by                      |
| ------------ | ---------------------------- |
| 1Password    | `config` (`gpg.ssh.program`) |
| GPG (`gpg2`) | `config` (`gpg.program`)     |
