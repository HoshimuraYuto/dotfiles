#!/usr/bin/env bash
# Link this directory's rules and skills into ~/.claude.
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

link "$src/rules" "$dest/rules/dotfiles"

for d in "$src"/skills/*/; do
  [[ -d $d ]] && link "${d%/}" "$dest/skills/$(basename "$d")"
done

exit $failed
