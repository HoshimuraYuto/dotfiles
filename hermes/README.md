# Hermes

Settings for each
[Hermes profile](https://hermes-agent.nousresearch.com/docs/user-guide/profiles)
(`default` is `~/.hermes`) can hold personal data, so they live in a separate
private repository cloned to `~/dotfiles-private` (override with
`DOTFILES_PRIVATE`). This public repository keeps only the installer.

```
~/dotfiles-private/hermes/profiles/<name>/
  config.txt    settings that differ from the Hermes defaults
  plugins.txt   catalog plugins
  skills/       the profile's own and edited bundled skills
~/dotfiles-private/hermes/skills/
  skills shared by every profile (second skills.external_dirs entry)
```

`install.sh` first runs `npm install` in the private repository, which sets up
its own git hooks (gitleaks, prettier, commitlint). It then creates missing
profiles and applies, per profile, `plugins.txt`
with `hermes plugins install`, then `config.txt` with `hermes config set`.
`config.yaml` is not linked because Hermes rewrites it.

```sh
./hermes/install.sh -n # preview
./hermes/install.sh
```

Each `config.txt` points `skills.create_dir` and the first `skills.external_dirs`
entry at the profile's `skills/` in the private repository, so Hermes creates
new skills there and edits and deletes change those files; every change shows up
in `git status` of the private repository. Keep edited bundled skills there too:
with the repo copy in `external_dirs`, `hermes update` no longer restores the
stock version over it. `install.sh -n` reports skills left in the profile's own
`skills/` that are neither unmodified bundled skills nor in the repository as
`UNMANAGED`, and a local copy of a repository skill, which would win, as
`CONFLICT`; move it aside first.

To manage a new profile, add a directory in the private repository;
`scripts/check.sh` lists profiles that have none and uncommitted changes in both
repositories.

Never put `.env`, `auth.json`, `memories/`, sessions, cron jobs or anything else
that holds secrets in either repository. The pre-commit hook scans staged changes
with gitleaks; it finds secrets, not personal details, which is what the private
repository and a skill loaded through `skills.auto_load` are for.

## Requirements

Installed separately, not by `install.sh`.

|                                  | Used by            |
| -------------------------------- | ------------------ |
| Hermes                           | `install.sh`       |
| jq                               | `install.sh`       |
| `~/dotfiles-private` (git clone) | `install.sh`       |
| Node                             | `install.test.mjs` |

## Checks

```sh
node --test hermes/install.test.mjs
```
