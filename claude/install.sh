#!/usr/bin/env bash
# Link this directory's rules and skills into ~/.claude, and install the
# external skills listed in external-skills.txt.
# ~/.claude/rules and ~/.claude/skills stay real directories -- Claude Code writes
# into them itself (skills/synced). Only the entries below are ours.
# Run with -n to preview.
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
dry=false
[[ ${1-} == -n || ${1-} == --dry-run ]] && dry=true

failed=0

link() {
  local from=$1 to=$2 name=${2#"$dest"/}
  if [[ -L $to ]]; then
    [[ $(readlink "$to") == "$from" ]] && {
      echo "ok         $name"
      return
    }
    echo "CONFLICT   $name -> $(readlink "$to")"
    failed=1
    return
  fi
  if [[ -e $to ]]; then
    echo "CONFLICT   $name exists and is not a symlink"
    failed=1
    return
  fi
  $dry && {
    echo "would link $name"
    return
  }
  mkdir -p "$(dirname "$to")"
  ln -s "$from" "$to"
  echo "linked     $name"
}

# `skills add --global` always writes to ~/.claude, so with CLAUDE_CONFIG_DIR set
# elsewhere the entry never appears at $dest and every run reinstalls it.
add() {
  local spec=$1 name=$2
  if [[ -e $dest/skills/$name ]]; then
    echo "ok         skills/$name"
    return
  fi
  $dry && {
    echo "would add  skills/$name"
    return
  }
  if npx --no -- skills add "$spec" --skill "$name" --agent claude-code --global --yes \
    > /dev/null 2>&1 < /dev/null; then
    echo "added      skills/$name"
  else
    echo "FAILED     skills/$name <- $spec"
    failed=1
  fi
}

link "$src/rules" "$dest/rules/dotfiles"

for d in "$src"/skills/*/; do
  [[ -d $d ]] && link "${d%/}" "$dest/skills/$(basename "$d")"
done

while read -r spec name _; do
  [[ -z $spec || $spec == \#* ]] && continue
  add "$spec" "$name"
done < "$src/external-skills.txt"

exit $failed
