#!/usr/bin/env bash
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dry=false
case ${1-} in
  -n | --dry-run) dry=true ;;
  "") ;;
  *)
    echo "Usage: $0 [-n|--dry-run]" >&2
    exit 2
    ;;
esac

if $dry; then
  brew bundle check --no-upgrade --file="$src/Brewfile" --verbose || true
else
  brew bundle install --no-upgrade --file="$src/Brewfile"
fi
