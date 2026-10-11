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

for file in .zprofile .zshrc .p10k.zsh; do
  link "$src/$file" "$HOME/$file"
done
exit "$failed"
