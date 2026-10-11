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

dest=${XDG_CONFIG_HOME:-$HOME/.config}/git
for file in config ignore; do
  link "$src/$file" "$dest/$file"
done
exit "$failed"
