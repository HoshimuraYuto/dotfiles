#!/usr/bin/env bash
# Usage: scan-leaks.sh <repo>
# Scans what pushing <repo> would publish, with <repo>'s own secretlint and config:
# tracked files, plus lines added by unpushed commits (a value removed again stays in history).
# Prints masked findings and exits 1 when there are any; exits 2 when the scan cannot run.
set -uo pipefail

repo=$1
lint=$repo/node_modules/.bin/secretlint
if [[ ! -x $lint ]]; then
  echo "secretlint is not installed in $repo (run npm install there)"
  exit 2
fi
cd -P "$repo" || exit 2

# Symlinks are skipped: their targets are tracked files scanned on their own
files=()
while IFS= read -r -d '' f; do
  [[ -f $f && ! -L $f ]] && files+=("$f")
done < <(git ls-files -z)

found=0
report() {
  local out status
  out=$("$lint" --no-color --no-terminalLink --format compact "$@" 2>&1)
  status=$?
  case $status in
    0) ;;
    1)
      grep -E ': line [0-9]+' <<< "$out" | sed "s|^$PWD/||"
      found=1
      ;;
    *)
      echo "secretlint failed in $repo:"
      head -5 <<< "$out"
      exit 2
      ;;
  esac
}

report --no-glob "${files[@]}"
report --stdinFileName unpushed-commits.diff \
  < <(git log -p --format= '@{upstream}..' 2> /dev/null | grep '^+')

exit "$found"
