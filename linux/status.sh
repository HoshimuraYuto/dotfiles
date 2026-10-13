#!/usr/bin/env bash
# Read-only report of what linux/install.sh set up, safe to paste: ports,
# addresses, the host name and the user name are replaced before printing.
set -uo pipefail

user=$(id -un)
host=$(hostname)
ssh_conf=/etc/ssh/sshd_config.d/50-dotfiles.conf
vnc_conf=$HOME/.vnc/tigervnc.conf
unit=tigervncserver@:1.service
ssh_port=$(sed -n 's/^Port \([0-9]*\)$/\1/p' "$ssh_conf" 2> /dev/null)
vnc_port=$(sed -n 's/^\$rfbport = \([0-9]*\);$/\1/p' "$vnc_conf" 2> /dev/null)

line() { printf '%-5s %s\n' "$1" "$2"; }
# Root-only reads are tried without a password prompt so that
# `ssh <host> ~/dotfiles/linux/status.sh | pbcopy` works.
root() { sudo -n "$@" 2> /dev/null; }

report() {
  echo "## linux/status.sh"
  echo "Ports, addresses, host and user names are replaced. Paste all of it."
  echo

  listening=$(ss -ltnH | awk '{print $4}')
  if [[ -z $ssh_port ]]; then
    line NG "SSH: $ssh_conf missing; run linux/install.sh"
  elif grep -q ":$ssh_port\$" <<< "$listening"; then
    line ok "SSH: listening on $ssh_port"
  else
    line NG "SSH: nothing listens on $ssh_port"
  fi
  if grep -q ':22$' <<< "$listening"; then
    line NG "SSH: port 22 still listening"
  fi
  case $(sed -n 's/^PasswordAuthentication //p' "$ssh_conf" 2> /dev/null) in
    no) line ok "SSH: password login off" ;;
    yes) line info "SSH: password login on (no key yet; run install.sh after ssh-copy-id)" ;;
  esac

  if status=$(root ufw status); then
    open=$(grep -E 'ALLOW|LIMIT' <<< "$status" | grep -v '(v6)' | awk '{print $1}' | paste -sd ' ' -)
    if grep -q '^Status: active' <<< "$status"; then
      line ok "ufw: active, open: ${open:-none}"
    else
      line NG "ufw: inactive"
    fi
  elif grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2> /dev/null; then
    line ok "ufw: enabled (rules need sudo to read)"
  else
    line NG "ufw: not enabled"
  fi

  if [[ -z $vnc_port ]]; then
    line NG "VNC: $vnc_conf missing; run linux/install.sh"
  fi
  state=$(systemctl is-active "$unit")
  if [[ $state == active ]]; then
    line ok "VNC: $unit active"
  else
    line NG "VNC: $unit $state ($(systemctl show -p Result --value "$unit"))"
  fi
  if [[ -n $vnc_port ]]; then
    if grep -qx "127.0.0.1:$vnc_port" <<< "$listening"; then
      line ok "VNC: listening on 127.0.0.1:$vnc_port"
    else
      line NG "VNC: nothing listens on 127.0.0.1:$vnc_port"
    fi
  fi
  if pgrep -u "$user" -x xfce4-session > /dev/null; then
    line ok "VNC: XFCE session running"
  else
    line NG "VNC: no XFCE session"
  fi
  [[ -s $HOME/.vnc/passwd ]] || line NG "VNC: ~/.vnc/passwd missing; run tigervncpasswd"

  echo
  echo "--- sessions of $user"
  loginctl list-sessions --no-legend 2> /dev/null | awk -v u="$user" '$3 == u {print $1}' \
    | while read -r id; do
      echo "$id $(loginctl show-session "$id" -p Type -p Class -p Service -p State --value | paste -sd ' ' -)"
    done

  echo
  echo "--- $unit journal, this boot"
  # Without sudo or the adm group journalctl prints "No entries" instead of failing
  root journalctl -b -u "$unit" -n 30 --no-pager \
    || journalctl -b -u "$unit" -n 30 --no-pager 2>&1

  echo
  echo "--- ~/.vnc/$host:1.log"
  tail -n 40 "$HOME/.vnc/$host:1.log" 2> /dev/null | grep -v 'Could not resolve keysym' \
    || echo "(none)"
}

redact() {
  SSH_PORT=$ssh_port VNC_PORT=$vnc_port H=$host U=$user perl -pe '
    s/\b$ENV{SSH_PORT}\b/<SSH_PORT>/g if $ENV{SSH_PORT};
    s/\b$ENV{VNC_PORT}\b/<VNC_PORT>/g if $ENV{VNC_PORT};
    s/\Q$ENV{H}\E/<HOST>/g;
    s/\b\Q$ENV{U}\E\b/<USER>/g;
    s/\b(?!127\.|0\.0\.0\.0\b)\d{1,3}(?:\.\d{1,3}){3}\b/<IP>/g;
  '
}

report 2>&1 | redact
