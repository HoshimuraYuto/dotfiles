#!/usr/bin/env bash
# Report drift between this repo and the current machine. Prints nothing when in sync.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
private=${DOTFILES_PRIVATE:-$HOME/dotfiles-private}
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

if command -v hermes > /dev/null; then
  section "Hermes settings not applied" \
    "$("$repo/hermes/install.sh" -n 2>&1 | grep -E '^(CONFLICT|UNMANAGED|MISSING|would (set|add)|INVALID)')"
  # The private repository's hooks must be installed, or its commits skip the secret scan
  [[ -f $private/package.json ]] \
    && section "Git hooks missing in the private repo" \
      "$(for hook in pre-commit commit-msg; do
        [[ -x $private/.git/hooks/$hook ]] || echo "$hook (run npm install in $private)"
      done)"
  # Machine -> repo: every profile on this Mac should have a directory in the private repo.
  # Profiles are default (~/.hermes) plus each directory under ~/.hermes/profiles.
  section "Hermes profiles not in the private repo" \
    "$(for p in default "$HOME"/.hermes/profiles/*/; do
      p=$(basename "$p")
      [[ $p == '*' || -d $private/hermes/profiles/$p ]] || echo "$p"
    done)"
fi

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
# Hermes writes skills straight into the private repo, so its changes are drift too
[[ -d $private/.git ]] \
  && section "Uncommitted changes in the private repo" "$(git -C "$private" status --short)"

exit "$drift"
