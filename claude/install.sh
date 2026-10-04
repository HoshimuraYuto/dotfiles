#!/usr/bin/env bash
set -euo pipefail

src=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$src/.." && pwd)
dest=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
skills_dest=$dest/skills
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

link "$src/rules" "$dest/rules/dotfiles"
install_skills claude-code "$src/skills" "$HOME/.claude/skills"
exit "$failed"
