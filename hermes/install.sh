#!/usr/bin/env bash
set -euo pipefail

dry=false
case ${1-} in
  -n | --dry-run) dry=true ;;
  "") ;;
  *)
    echo "Usage: $0 [-n|--dry-run]" >&2
    exit 2
    ;;
esac
failed=0

# Settings and skills hold personal data, so they live in a private repository;
# this public one keeps only the installer.
private=${DOTFILES_PRIVATE:-$HOME/dotfiles-private}
profiles=$private/hermes/profiles
if [[ ! -d $profiles ]]; then
  echo "MISSING    $profiles (clone the private repository first)"
  exit 1
fi

# The private repository has its own git hooks (gitleaks, prettier, commitlint)
if [[ -f $private/package.json ]]; then
  if $dry; then
    echo "would run  npm install in $private"
  else
    (cd "$private" && mise exec -- npm install)
  fi
fi

# hermes reads stdin, so every call gets /dev/null to keep the loops' input intact
h() {
  hermes -p "$profile" "$@" < /dev/null
}

# Values in config.txt are JSON; a string starting with ~/ is relative to $HOME
want_json() {
  jq -c --arg home "$HOME" 'walk(if type == "string" then sub("^~/"; $home + "/") else . end)' <<< "$1"
}

check_skills() {
  local md skill copy
  [[ -d $dir/skills ]] || return 0
  while IFS= read -r md; do
    skill=$(basename "$(dirname "$md")")
    copy=$(find "$home/skills" -path "$home/skills/.*" -prune -o -path "*/$skill/SKILL.md" -print -quit 2> /dev/null || true)
    if [[ -n $copy ]]; then
      echo "CONFLICT   $profile: ${copy%/SKILL.md} shadows the repo skill"
      failed=1
    fi
  done < <(find "$dir/skills" -name SKILL.md)
}

# Machine -> repo: skills in the profile's own skills/ that the repo does not hold.
# Unmodified bundled skills belong to Hermes; anything else (new or edited) should
# move into the repo, where create_dir and external_dirs keep later changes.
check_local() {
  local md skill
  while IFS= read -r md; do
    skill=$(basename "$(dirname "$md")")
    # A copy of a repo skill is already reported by check_skills
    [[ -n $(find "$dir/skills" -path "*/$skill/SKILL.md" -print -quit 2> /dev/null || true) ]] && continue
    grep -qsx "$skill:.*" "$home/skills/.bundled_manifest" && continue
    echo "UNMANAGED  $profile: ${md%/SKILL.md}"
    failed=1
  done < <(find "$home/skills" -path "$home/skills/.*" -prune -o -name SKILL.md -print 2> /dev/null || true)
  while read -r skill; do
    [[ -n $(find "$dir/skills" -path "*/$skill/SKILL.md" -print -quit 2> /dev/null || true) ]] && continue
    echo "UNMANAGED  $profile: $skill (edited bundled skill)"
    failed=1
  done < <(h skills list-modified 2> /dev/null | sed -n 's/^ *~ //p')
}

install_plugins() {
  local plugin extra
  [[ -f $dir/plugins.txt ]] || return 0
  while read -r plugin extra; do
    [[ -z $plugin || $plugin == \#* ]] && continue
    if grep -qsF "\"catalog_name\": \"$plugin\"" "$home"/plugins/*/.hermes-catalog.json; then
      echo "ok         $profile: plugin $plugin"
    elif $dry; then
      echo "would add  $profile: plugin $plugin"
    elif h plugins install "$plugin" --enable --yes-deps > /dev/null; then
      echo "added      $profile: plugin $plugin"
    else
      echo "FAILED     $profile: plugin $plugin"
      failed=1
    fi
  done < "$dir/plugins.txt"
}

apply_config() {
  local key value want have
  [[ -f $dir/config.txt ]] || return 0
  while read -r key value; do
    [[ -z $key || $key == \#* ]] && continue
    if ! want=$(want_json "$value" 2> /dev/null) || [[ -z $want ]]; then
      echo "INVALID    $profile: $key $value"
      failed=1
      continue
    fi
    have=$(h config get --json "$key" 2> /dev/null | jq -c . 2> /dev/null || true)
    if [[ $have == "$want" ]]; then
      echo "ok         $profile: $key"
    elif $dry; then
      echo "would set  $profile: $key"
    elif h config set "$key" "$(jq -r 'if type == "string" then . else tojson end' <<< "$want")" > /dev/null; then
      echo "set        $profile: $key"
    else
      echo "FAILED     $profile: $key"
      failed=1
    fi
  done < "$dir/config.txt"
}

for dir in "$profiles"/*/; do
  dir=${dir%/}
  profile=$(basename "$dir")
  if ! h config path > /dev/null 2>&1; then
    if $dry; then
      echo "would add  profile $profile"
      continue
    fi
    if ! hermes profile create "$profile" --no-skills < /dev/null > /dev/null; then
      echo "FAILED     profile $profile"
      failed=1
      continue
    fi
    echo "added      profile $profile"
  fi
  home=$(dirname "$(h config path)")
  check_skills
  check_local
  # Plugins first: a plugin can provide the model.provider that config.txt selects
  install_plugins
  apply_config
done
exit "$failed"
