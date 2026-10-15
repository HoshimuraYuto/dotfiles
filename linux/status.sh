#!/usr/bin/env bash
# Read-only report of what linux/install.sh set up, safe to paste: ports,
# addresses, the host name and the user name are replaced before printing.
set -uo pipefail

user=$(id -un)
host=$(hostname)
ssh_conf=/etc/ssh/sshd_config.d/50-dotfiles.conf
schema=org.gnome.desktop.remote-desktop.rdp
unit=gnome-remote-desktop.service
# Over SSH the GNOME session's bus is not in the environment; it is the user bus
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
ssh_port=$(sed -n 's/^Port \([0-9]*\)$/\1/p' "$ssh_conf" 2> /dev/null)
rdp_port=$(gsettings get "$schema" port 2> /dev/null | sed 's/^uint16 //')

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
    if [[ -n $rdp_port ]] && grep -q "^$rdp_port/" <<< "$status"; then
      line NG "ufw: RDP port is open to the network"
    fi
  elif grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2> /dev/null; then
    line ok "ufw: enabled (rules need sudo to read)"
  else
    line NG "ufw: not enabled"
  fi

  if [[ ! -S $XDG_RUNTIME_DIR/bus ]]; then
    line NG "RDP: no session bus; nobody is logged in to the desktop"
  elif [[ $(gsettings get "$schema" enable 2> /dev/null) == true ]]; then
    line ok "RDP: enabled"
  else
    line NG "RDP: disabled; run linux/install.sh"
  fi
  [[ $(gsettings get "$schema" view-only 2> /dev/null) == false ]] \
    || line NG "RDP: view-only (no mouse or keyboard)"
  state=$(systemctl --user is-active "$unit" 2> /dev/null)
  if [[ $state == active ]]; then
    line ok "RDP: $unit active"
  else
    line NG "RDP: $unit ${state:-unknown}"
  fi
  if [[ -n $rdp_port ]] && grep -q ":$rdp_port\$" <<< "$listening"; then
    line ok "RDP: listening on $rdp_port"
  else
    line NG "RDP: nothing listens on ${rdp_port:-its port}"
  fi
  case $(timeout 20 grdctl status 2> /dev/null | sed -n 's/^\s*Username: //p') in
    "(hidden)") line ok "RDP: credentials stored" ;;
    "") line NG "RDP: grdctl status failed (login keyring locked?)" ;;
    *) line NG "RDP: no credentials; run linux/install.sh" ;;
  esac
  ext=allowlockedremotedesktop@kamens.us
  if [[ ! -f $HOME/.local/share/gnome-shell/extensions/$ext/metadata.json ]]; then
    line NG "RDP while locked: extension not installed; run linux/install.sh"
  elif ! gsettings get org.gnome.shell enabled-extensions 2> /dev/null | grep -qF "'$ext'"; then
    line NG "RDP while locked: extension not enabled; run linux/install.sh"
  elif gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Extensions.GetExtensionInfo "$ext" 2> /dev/null | grep -q "'state': <1.0>"; then
    line ok "RDP while locked: extension active"
  else
    # Locking and unlocking keeps the same shell; only logging out starts a new one
    shell_pid=$(pgrep -u "$(id -u)" -xn gnome-shell)
    shell_start=$(($(date +%s) - $(ps -o etimes= -p "$shell_pid" 2> /dev/null || echo 0)))
    installed_at=$(stat -c %Y "$HOME/.local/share/gnome-shell/extensions/$ext")
    if [[ -z $shell_pid ]]; then
      line NG "RDP while locked: GNOME Shell is not running for this user"
    elif ((shell_start < installed_at)); then
      line NG "RDP while locked: GNOME Shell started before the extension was installed; log out (lock and unlock is not enough) or reboot"
    else
      line NG "RDP while locked: GNOME Shell did not load the extension; see journalctl --user -b _COMM=gnome-shell"
    fi
  fi
  if [[ -f /etc/tigervnc/vncserver.users ]] && grep -q "=$user *\$" /etc/tigervnc/vncserver.users; then
    line NG "VNC: an earlier TigerVNC session is still configured; run linux/install.sh"
  fi

  echo
  echo "--- sessions of $user"
  loginctl list-sessions --no-legend 2> /dev/null | awk -v u="$user" '$3 == u {print $1}' \
    | while read -r id; do
      echo "$id $(loginctl show-session "$id" -p Type -p Class -p Service -p State -p LockedHint --value | paste -sd ' ' -)"
    done

  echo
  echo "--- $unit journal, this boot"
  journalctl --user -b -u "$unit" -n 30 --no-pager 2>&1
}

redact() {
  SSH_PORT=$ssh_port RDP_PORT=$rdp_port H=$host U=$user perl -pe '
    s/\b$ENV{SSH_PORT}\b/<SSH_PORT>/g if $ENV{SSH_PORT};
    s/\b$ENV{RDP_PORT}\b/<RDP_PORT>/g if $ENV{RDP_PORT};
    s/\Q$ENV{H}\E/<HOST>/g;
    s/\b\Q$ENV{U}\E\b/<USER>/g;
    s/\b(?!127\.|0\.0\.0\.0\b)\d{1,3}(?:\.\d{1,3}){3}\b/<IP>/g;
  '
}

report 2>&1 | redact
