#!/usr/bin/env bash
# Sourced by each installer; callers set dry, plus repo and skills_dest for install_skills.

failed=0

link() {
  local from=$1 to=$2
  if [[ -L $to ]]; then
    if [[ $(readlink "$to") == "$from" ]]; then
      echo "ok         $to"
      return
    fi
    echo "CONFLICT   $to -> $(readlink "$to")"
    failed=1
    return
  fi
  if [[ -e $to ]]; then
    echo "CONFLICT   $to exists and is not a symlink"
    failed=1
    return
  fi
  if $dry; then
    echo "would link $to"
    return
  fi
  mkdir -p "$(dirname "$to")"
  ln -s "$from" "$to"
  echo "linked     $to"
}

install_skills() {
  local agent=$1 source_dir=$2 global_dir=$3 d spec name extra
  for d in "$source_dir"/*/; do
    [[ -d $d ]] && link "${d%/}" "$skills_dest/$(basename "$d")"
  done

  while read -r spec name extra; do
    [[ -z $spec || $spec == \#* ]] && continue
    if [[ -z $name || -n $extra || $spec != *#?* || ! $name =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      echo "INVALID    external skill: $spec $name"
      failed=1
      continue
    fi
    if [[ -L $skills_dest/$name && ! -e $skills_dest/$name ]]; then
      echo "CONFLICT   $skills_dest/$name is a dangling symlink"
      failed=1
      continue
    fi
    if [[ -e $skills_dest/$name/SKILL.md ]]; then
      echo "ok         $skills_dest/$name"
      continue
    fi
    if [[ -e $skills_dest/$name ]]; then
      echo "CONFLICT   $skills_dest/$name is not a skill"
      failed=1
      continue
    fi
    if $dry; then
      echo "would add  $skills_dest/$name <- $spec"
      continue
    fi
    if [[ ! -e $global_dir/$name/SKILL.md ]]; then
      # A shell opened before mise/install.sh has no Node on PATH yet
      if ! command -v npx > /dev/null && command -v mise > /dev/null; then
        eval "$(mise env -s bash)"
      fi
      if ! (cd "$repo" && npx --no -- skills add "$spec" --skill "$name" --agent "$agent" --global --yes); then
        echo "FAILED     $name <- $spec"
        failed=1
        continue
      fi
    fi
    if [[ ! -e $global_dir/$name/SKILL.md ]]; then
      echo "FAILED     skills CLI did not install $global_dir/$name"
      failed=1
    elif [[ $skills_dest != "$global_dir" ]]; then
      link "$global_dir/$name" "$skills_dest/$name"
    else
      echo "added      $skills_dest/$name"
    fi
  done < "$repo/external-skills.txt"
}
