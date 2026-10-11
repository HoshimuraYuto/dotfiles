#!/usr/bin/env bash
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$src/.." && pwd)
dry=false
case ${1-} in
  -n | --dry-run) dry=true ;;
  "") ;;
  *)
    echo "Usage: $0 [-n|--dry-run]" >&2
    exit 2
    ;;
esac
source "$repo/scripts/install-agent.sh"

config=${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml
link "$src/config.toml" "$config"
if ((failed)); then
  exit "$failed"
fi

if $dry; then
  # The link may not exist yet, so read the repo config directly
  MISE_GLOBAL_CONFIG_FILE=$src/config.toml mise install --dry-run --cd "$HOME"
  echo "would run  npm install in $repo"
else
  mise install --cd "$HOME"
  # The calling shell has not activated mise yet, so run npm through it
  (cd "$repo" && mise exec -- npm install)
fi
