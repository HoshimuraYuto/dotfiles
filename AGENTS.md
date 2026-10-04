# AGENTS.md

## Adding something new

Anything new that depends on a tool the installers do not install → add it to
the Requirements table in the affected agent's README.

Shared skills belong in `skills/`; agent-specific `skills/` entries link to them.
Shared prose rules belong in `rules/`; Claude links to each rule and Codex
concatenates them with `codex/instructions.md` into its global `AGENTS.md`.
Re-run the Codex installer after editing shared rules, and the relevant
installer after adding a skill. Keep tool-specific instructions separate.

A skill from another repository is not vendored here. List it in
`external-skills.txt` with a pinned ref and the installers install it globally.
Whether it stays model-invocable is a separate decision: `skillOverrides` in
`claude/settings.json`, or `agents/openai.yaml` under `codex/skill-overrides/`.
Only overrides are tracked for external skills, never their fetched contents.
