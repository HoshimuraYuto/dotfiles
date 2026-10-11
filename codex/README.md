# Codex

Local Codex configuration, tested with CLI 0.162.1. Uses the current
[file-based profiles](https://learn.chatgpt.com/docs/config-file/config-advanced)
and [permission profiles](https://learn.chatgpt.com/docs/permissions).

## Setup

```sh
./mise/install.sh
./codex/install.sh -n # preview
./codex/install.sh
codex --profile dotfiles
```

The installer:

- Generates `~/.codex/AGENTS.md` from shared [`rules/`](../rules) and
  [`instructions.md`](instructions.md). Re-run after editing those sources.
- Links `dotfiles.config.toml` and `rules/dotfiles.rules` into `~/.codex/`.
- Links shared [`skills/`](../skills) into `~/.agents/skills/`. Codex follows
  [symlinked skill directories](https://learn.chatgpt.com/docs/build-skills).
- Installs the pinned [`external-skills.txt`](../external-skills.txt) entries
  with the skills CLI and links in Codex invocation-policy metadata.

`~/.codex/config.toml`, existing plugins, MCP settings, and `rules/default.rules`
stay local. The dotfiles profile overlays the base config without choosing a
model. A non-empty unmanaged global `AGENTS.md`, different symlinks, or existing
policy metadata are reported as conflicts and preserved.

Global instructions, command rules, and skills load independently of selecting
the profile. `AGENTS.override.md`, project settings, CLI flags, and managed
requirements can change the effective configuration. Inspect `/debug-config`
and `/status` when diagnosing differences.

`DOTFILES_CODEX_DIR` changes the install destination (defaults to `CODEX_HOME`,
then `~/.codex`). `DOTFILES_SKILLS_DIR` changes the skills destination (defaults
to `~/.agents/skills`). External downloads still use the CLI's global location
and are linked into a custom destination if needed. Existing external skills
are retained; after changing a pinned ref, reinstall that skill at the new ref.

## Differences from Claude

- Auto-review handles approval requests at the sandbox boundary; ordinary
  workspace work proceeds inside the sandbox.
- Permission profiles are Beta. Do not combine this profile with `sandbox_mode`,
  `sandbox_workspace_write`, or `--sandbox`: those older settings take precedence
  over `default_permissions`. Workspace `.env` and `.env.*` files, `~/.aws`,
  `~/.ssh`, `~/.bashrc`, and `~/.zshrc` are denied to sandboxed commands.
- Command rules use argument prefixes and control execution outside the
  sandbox. They do not reproduce arbitrary Claude shell wildcards, such as
  `--force` after remote/branch arguments, `/etc/shadow*`, or interpreter options
  reordered before `-c`/`-e`. Instructions also forbid force-pushing; this is
  behavioral guidance, not an equivalent enforcement guarantee.
- Claude's `WebFetch` allow entries are not a global network allowlist. This
  profile keeps command networking subject to the workspace sandbox and
  approval flow, and uses live built-in web search. It adds no network proxy.
- `security-audit` remains explicitly invocable as `$security-audit` with
  `allow_implicit_invocation: false`. External skill contents are not copied
  into this repository.
- The CLI status line uses built-in model, directory, branch, context, and rate
  limit fields. The Claude status-line script and its cost/time/change counts
  are not used. `/statusline` configures the available fields interactively.
- `history.persistence = "save-all"` enables CLI history persistence. It does
  not promise Claude's `cleanupPeriodDays` retention behavior. Claude marketplace
  declarations are not translated; existing Codex plugins remain configured.

## Requirements

Installed separately, not by `install.sh`.

|               | Used by                                 |
| ------------- | --------------------------------------- |
| Codex CLI     | profiles, rules, skills, sandbox        |
| agent-browser | Web research, shared `skills/context7`  |
| jq            | shared `skills/context7`                |
| Node          | `install.sh`, external `security-audit` |

## Checks

```sh
node --test scripts/install-agent.test.mjs
codex execpolicy check --rules codex/rules/dotfiles.rules -- git reset --hard HEAD
```

The rule check evaluates policy without running the command.
