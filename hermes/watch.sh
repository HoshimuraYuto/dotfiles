#!/usr/bin/env bash
# Run by the launch agent hermes/install.sh writes: applies the shared settings to a
# Hermes profile as soon as it is created. Usage: watch.sh <Hermes root>
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$1

# fswatch on a path that does not exist yet reports nothing, and Hermes creates
# profiles/ only with the first named profile
mkdir -p "$root/profiles"

# Visible profile directories; Hermes builds a profile in a hidden staging
# directory and renames it into place
list() {
  find "$root/profiles" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec basename {} \; | sort
}

# Catches profiles created while the agent was not running (before login, say)
"$here/install.sh" --auto
known=$(list)

# fswatch's default FSEvents monitor misses some new directories when it runs under
# launchd; the kqueue monitor reported each one. kqueue names only the watched
# directory, not the entry that changed, so new profiles are found by comparing
# listings and only those are configured.
fswatch -m kqueue_monitor -o -l 0.2 "$root/profiles" | while read -r _; do
  now=$(list)
  new=$(comm -13 <(echo "$known") <(echo "$now"))
  known=$now
  [[ -n $new ]] || continue
  # Profile names are [a-z0-9_-], so word splitting is safe
  # shellcheck disable=SC2086
  "$here/install.sh" --auto $new
done
