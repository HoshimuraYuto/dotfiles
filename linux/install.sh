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
if ((EUID == 0)); then
  echo "Run as the desktop user; the VNC session belongs to the user who runs this." >&2
  exit 2
fi

failed=0
user=$(id -un)
ssh_conf=/etc/ssh/sshd_config.d/50-dotfiles.conf
vnc_conf=$HOME/.vnc/tigervnc.conf
vnc_users=/etc/tigervnc/vncserver.users
vnc_display=:1
marker='Managed by dotfiles linux/install.sh'

# --- Packages

wanted=$(grep -vE '^\s*(#|$)' "$src/packages.txt")
# shellcheck disable=SC2086
missing=$(for p in $wanted; do
  dpkg-query -W -f='${db:Status-Status}' "$p" 2> /dev/null | grep -qx installed || echo "$p"
done)
if [[ -z $missing ]]; then
  echo "ok         packages"
elif $dry; then
  echo "would install $(echo $missing)"
else
  sudo apt-get update
  # shellcheck disable=SC2086
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $missing
fi
if $dry && [[ -n $missing ]]; then
  echo "Packages are missing; the rest of the preview is skipped."
  exit 0
fi

# --- Ports: random on the first run, then kept from the files written below

listening() { ss -ltnH | awk '{print $4}' | sed 's/.*://' | sort -u; }

random_port() {
  local p used
  used=$(listening)
  while :; do
    # 10000-32767: above common services, below the kernel's ephemeral range
    p=$(shuf -i 10000-32767 -n 1)
    grep -qx "$p" <<< "$used" || [[ $p == "${1-}" ]] || break
  done
  echo "$p"
}

valid_port() { [[ $1 =~ ^[0-9]+$ ]] && (($1 >= 1024 && $1 <= 65535)); }

current_ssh=$(sed -n 's/^Port \([0-9]*\)$/\1/p' "$ssh_conf" 2> /dev/null || true)
current_vnc=$(sed -n 's/^\$rfbport = \([0-9]*\);$/\1/p' "$vnc_conf" 2> /dev/null || true)
ssh_port=${SSH_PORT:-${current_ssh:-$(random_port)}}
vnc_port=${VNC_PORT:-${current_vnc:-$(random_port "$ssh_port")}}
for p in "$ssh_port" "$vnc_port"; do
  if ! valid_port "$p"; then
    echo "INVALID    port $p (1024-65535)" >&2
    exit 2
  fi
done
if [[ $ssh_port == "$vnc_port" ]]; then
  echo "INVALID    SSH and VNC share port $ssh_port" >&2
  exit 2
fi

fill() {
  local content
  content=$(< "$src/$1")
  content=${content//@SSH_PORT@/"$ssh_port"}
  content=${content//@VNC_PORT@/"$vnc_port"}
  content=${content//@PASSWORD_AUTH@/"$password_auth"}
  printf '%s' "$content"
}

# Writes $2 to $1 when it differs; sets changed=true. $3 = "sudo" for system files.
put() {
  local dest=$1 content=$2 as=${3-}
  changed=false
  if [[ -f $dest && $(< "$dest") == "$content" ]]; then
    echo "ok         $dest"
    return
  fi
  if [[ -f $dest ]] && ! head -1 "$dest" | grep -qF "$marker"; then
    echo "CONFLICT   $dest exists and is not managed by dotfiles"
    failed=1
    return
  fi
  changed=true
  if $dry; then
    echo "would write $dest"
    return
  fi
  $as mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" | $as tee "$dest" > /dev/null
  echo "wrote      $dest"
}

# --- Firewall: open the new SSH port before sshd moves to it

rule="ufw limit $ssh_port/tcp comment 'dotfiles-ssh'"
added=$(sudo ufw show added)
if grep -qxF "$rule" <<< "$added"; then
  echo "ok         ufw: $ssh_port/tcp"
elif $dry; then
  echo "would run  ufw limit $ssh_port/tcp"
else
  sudo ufw limit "$ssh_port/tcp" comment dotfiles-ssh
fi
status=$(sudo ufw status verbose)
if grep -q '^Status: active' <<< "$status" && grep -q 'deny (incoming), allow (outgoing)' <<< "$status"; then
  echo "ok         ufw: active, deny incoming"
elif $dry; then
  echo "would run  ufw default deny incoming; ufw default allow outgoing; ufw enable"
else
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw --force enable
fi

# --- SSH: key-only once the user has an authorized key, so the switch cannot lock them out

if grep -qE '^(ssh-|ecdsa-|sk-)' "$HOME/.ssh/authorized_keys" 2> /dev/null; then
  password_auth=no
else
  password_auth=yes
fi
put "$ssh_conf" "$(fill sshd.conf)" sudo
if $changed && ! $dry; then
  # ssh.service creates /run/sshd, but with socket activation it may not have run yet
  sudo mkdir -p /run/sshd
  if ! sudo sshd -t; then
    sudo rm -f "$ssh_conf"
    echo "FAILED     sshd rejected $ssh_conf; removed it" >&2
    exit 1
  fi
  # Ubuntu's ssh.socket takes Port from sshd_config through a generator run by daemon-reload
  sudo systemctl daemon-reload
  sudo systemctl restart ssh.socket
fi
if ! $dry; then
  sudo systemctl enable --quiet ssh.socket
fi

# Remove rules for SSH ports this installer opened earlier
while read -r stale; do
  [[ -z $stale ]] && continue
  if $dry; then
    echo "would run  ufw delete limit $stale/tcp"
  else
    sudo ufw delete limit "$stale/tcp"
  fi
done < <(sed -n "s/^ufw limit \([0-9]*\)\/tcp comment 'dotfiles-ssh'$/\1/p" <<< "$added" | grep -vx "$ssh_port" || true)

# --- VNC: TigerVNC on localhost only, reached through an SSH tunnel

put "$vnc_conf" "$(fill tigervnc.conf)"
vnc_changed=$changed
put /etc/polkit-1/rules.d/50-dotfiles-colord.rules "$(< "$src/colord.rules")" sudo

# An X server already holds display N when /tmp/.XN-lock or its socket exists;
# the desktop's own Xwayland takes the lowest free numbers, starting at :0.
display_free() { [[ ! -e /tmp/.X$1-lock && ! -e /tmp/.X11-unix/X$1 ]]; }
display_ours() { systemctl is-active --quiet "tigervncserver@:$1.service" || display_free "$1"; }

mapped=$(sed -n "s/^ *:\([0-9]*\)=$user *\$/\1/p" "$vnc_users" | head -1)
if [[ -n $mapped ]] && display_ours "$mapped"; then
  vnc_display=:$mapped
  echo "ok         $vnc_users ($vnc_display)"
else
  if [[ -n $mapped ]]; then
    echo "TAKEN      display :$mapped is used by another X server"
  fi
  # Start well above the displays a desktop login uses
  n=10
  until display_free "$n" && ! grep -q "^ *:$n=" "$vnc_users"; do n=$((n + 1)); done
  vnc_display=:$n
  vnc_changed=true
  if $dry; then
    echo "would map  $vnc_display=$user in $vnc_users"
  else
    if [[ -n $mapped ]]; then
      sudo systemctl disable --now --quiet "tigervncserver@:$mapped.service" || true
      sudo sed -i "/^ *:$mapped=$user *\$/d" "$vnc_users"
    fi
    echo "$vnc_display=$user" | sudo tee -a "$vnc_users" > /dev/null
    echo "mapped     $vnc_display=$user in $vnc_users"
  fi
fi

if [[ -s $HOME/.vnc/passwd ]]; then
  echo "ok         ~/.vnc/passwd"
elif $dry; then
  echo "would ask  for a VNC password"
elif [[ -t 0 ]]; then
  echo "Set the VNC password (6-8 characters; VNC ignores the rest):"
  tigervncpasswd
else
  echo "MISSING    ~/.vnc/passwd; run tigervncpasswd, then this installer again"
  failed=1
fi

unit=tigervncserver@$vnc_display.service
if ! $dry && ((failed == 0)); then
  if $vnc_changed && systemctl is-active --quiet "$unit"; then
    sudo systemctl restart "$unit"
  fi
  sudo systemctl enable --now --quiet "$unit"
  # The unit reports success even when tigervncserver exits at once, so check the port
  for _ in {1..10}; do
    ss -ltnH | awk '{print $4}' | grep -qx "127.0.0.1:$vnc_port" && break
    sleep 1
  done
  if ss -ltnH | awk '{print $4}' | grep -qx "127.0.0.1:$vnc_port"; then
    echo "ok         VNC listening ($vnc_display)"
  else
    echo "FAILED     VNC is not listening; see linux/status.sh"
    failed=1
  fi
fi

# --- Summary

host=$(hostname)
cat << EOF

SSH port $ssh_port, VNC port $vnc_port (localhost only)
Add to ~/.ssh/config on the Mac:

  Host $host
    HostName $(hostname -I 2> /dev/null | awk '{print $1}')
    Port $ssh_port
    User $user
    IdentityFile ~/.ssh/id_ed25519_$host
    IdentitiesOnly yes
    LocalForward 5901 localhost:$vnc_port

IdentitiesOnly stops ssh offering every agent key first; sshd disconnects
after six with "Too many authentication failures".
Then: ssh $host, and open vnc://localhost:5901 while it is connected.
EOF
if [[ $password_auth == yes ]]; then
  cat << EOF

Password login is still on: no key in ~/.ssh/authorized_keys.
From the Mac, after adding the entry above:
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_$host
  ssh-copy-id -i ~/.ssh/id_ed25519_$host.pub $host
Then run this installer again to allow keys only.
EOF
fi
exit "$failed"
