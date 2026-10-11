# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input must go above this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

typeset -U path
# (N-/) skips directories that do not exist on this machine
path=(
  $HOME/.local/bin(N-/)
  $HOME/.antigravity/antigravity/bin(N-/)
  /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin(N-/)
  $path
  $HOME/.cache/lm-studio/bin(N-/)
)

eval "$(mise activate zsh)"

# $(tty) fails under instant prompt
export GPG_TTY=$TTY

fpath=($HOMEBREW_PREFIX/share/zsh-completions $fpath)
autoload -Uz compinit && compinit
zstyle ':completion:*:commands' rehash 1

source $HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh

alias claude='command claude --settings "$HOME/dotfiles/claude/settings.json"'
alias codex='command codex --profile dotfiles'

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Must be sourced last
source $HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
