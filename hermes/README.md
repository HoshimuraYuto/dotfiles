# Hermes

Settings for each
[Hermes profile](https://hermes-agent.nousresearch.com/docs/user-guide/profiles)
(`default` is `~/.hermes`) can hold personal data, so they live in a separate
private repository cloned to `~/dotfiles-private` (override with
`DOTFILES_PRIVATE`). This public repository keeps only the installer.

```
~/dotfiles-private/hermes/profiles/<name>/
  config.txt    settings that differ from the Hermes defaults
  plugins.txt   plugins for this profile only
  skills/       the profile's own and edited bundled skills
  external-skills.txt  skills from other repositories for this profile only
~/dotfiles-private/hermes/plugins.txt
  plugins for every profile
~/dotfiles-private/hermes/config.txt
  settings for every profile ({profile} = the profile's name)
~/dotfiles-private/hermes/skills/
  skills shared by every profile (second skills.external_dirs entry)
```

`install.sh` first runs `npm install` in the private repository, which sets up
its own git hooks (gitleaks, prettier, commitlint). It then creates missing
profiles and applies, per profile, the shared `plugins.txt` followed by the
profile's own, then `config.txt` with `hermes config set`. A plugin bundled with
Hermes is turned on with `hermes plugins enable`; any other is installed from
the catalog with `hermes plugins install`. Hermes has no setting that applies a
plugin to every profile, so the shared list is how new profiles get them too.
`config.yaml` is not linked because Hermes rewrites it.

Skills for every profile go in the private repository's `hermes/skills/`.
Skills from other repositories are listed in
[`external-skills.txt`](../external-skills.txt) as for Claude and Codex: the
Codex installer puts them in `~/.agents/skills`, which the shared `config.txt`
adds to `skills.external_dirs`. `hermes skills install` is not used, because it
installs into one profile only, and `install.sh -n` reports a plugin enabled
outside both plugin lists as `UNMANAGED`. To load a skill in full in every session, also
add it to `skills.auto_load` in the shared `config.txt`.

For one profile only, put the skill in the profile's `skills/` or, for a skill
from another repository, list it in the profile's `external-skills.txt` (same
format, ref pinned). `install.sh` installs those with the same `skills` CLI into
`~/.local/share/dotfiles/hermes/profiles/<name>/.agents/skills`, a directory
outside both repositories that the shared `config.txt` adds to
`skills.external_dirs` as `{profile}`'s own.

Shared settings come before the profile's own `config.txt`, which overrides a
key it repeats. Hermes profiles without a directory in the private repository,
such as a bot made in the desktop app, get the shared settings and plugins too.
Hermes has no hook for a new profile, so `install.sh` also loads a launch agent,
`dotfiles.hermes-sync`, that keeps [`watch.sh`](watch.sh) running: it watches
the profiles directory with `fswatch` and configures each new profile within a
few seconds. Every run checks that each skill in `skills.auto_load` is set and
present, and reports `NOT LOADED` (a notification for the agent's runs) until it
is; list a profile in the private repository's `hermes/skip-profiles.txt` to
leave it alone.

Hermes has no global instructions file (`SOUL.md` is the persona), so
`install.sh` generates the shared [`rules/`](../rules) plus the private
repository's optional `hermes/instructions.md` into a `dotfiles-rules` skill
under `~/.local/share/dotfiles/hermes/skills/`. The shared `config.txt` adds
that directory to `skills.external_dirs` and the skill to `skills.auto_load`.
Re-run after editing those sources.

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
| fswatch (`macos/Brewfile`)       | `watch.sh`         |
| `~/dotfiles-private` (git clone) | `install.sh`       |
| Node                             | `install.test.mjs` |

## Checks

```sh
node --test hermes/install.test.mjs
```
