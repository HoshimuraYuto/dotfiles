#!/usr/bin/env bash
# Report drift between this repo and the current machine. Prints nothing when in sync.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export HOMEBREW_NO_AUTO_UPDATE=1
drift=0

section() {
  local title=$1 body=$2
  [[ -z $body ]] && return
  printf '## %s\n%s\n\n' "$title" "$body"
  drift=1
}

# Repo -> machine: links the installers would create or cannot create
links=$(for d in zsh git mise claude codex; do
  "$repo/$d/install.sh" -n 2>&1 | grep -E '^(CONFLICT|would link|INVALID)' | sed "s|^|$d: |"
done)
section "Links not in place" "$links"

if command -v brew > /dev/null; then
  wanted=$(brew bundle list --formula --cask --file="$repo/macos/Brewfile" | sort)
  have=$( (
    brew list --formula --installed-on-request
    brew list --cask
  ) | sort)
  section "Brewfile packages not installed" "$(comm -23 <(echo "$wanted") <(echo "$have"))"
  section "Installed packages not in Brewfile" "$(comm -13 <(echo "$wanted") <(echo "$have"))"
fi

if command -v mise > /dev/null; then
  section "mise tools not installed" "$(cd "$HOME" && mise ls --global --missing 2> /dev/null)"
  section "npm global packages outside mise/config.toml" \
    "$(mise exec -- npm ls -g --depth=0 --parseable 2> /dev/null | sed 1d | xargs -n1 basename | grep -vxE 'npm|corepack')"
fi

# Machine -> repo: shared git settings belong in git/config, ~/.gitconfig keeps only [user]
section "~/.gitconfig keys outside [user]" \
  "$(git config --file "$HOME/.gitconfig" --name-only --list 2> /dev/null | grep -v '^user\.' | sort -u)"

section "Uncommitted changes in the repo" "$(git -C "$repo" status --short)"

exit "$drift"
