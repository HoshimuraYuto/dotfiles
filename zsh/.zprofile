# Homebrew's default prefixes on Apple Silicon and Linux
for brew in /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [[ -x $brew ]] && eval "$($brew shellenv)" && break
done
unset brew
