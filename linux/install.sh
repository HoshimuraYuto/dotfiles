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
  echo "Run as the desktop user; remote desktop shares that user's GNOME session." >&2
  exit 2
fi

failed=0
user=$(id -un)
host=$(hostname)
ssh_conf=/etc/ssh/sshd_config.d/50-dotfiles.conf
marker='Managed by dotfiles linux/install.sh'
rdp_schema=org.gnome.desktop.remote-desktop.rdp
rdp_dir=$HOME/.local/share/gnome-remote-desktop
# Over SSH the GNOME session's bus is not in the environment; it is the user bus
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}

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

# --- Ports: random on the first run, then kept from the settings written below

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

# gsettings prints "uint16 3389", "'/path'" or "true"; compare bare values
rdp_get() { gsettings get "$rdp_schema" "$1" 2> /dev/null | sed -e 's/^uint16 //' -e "s/^'\(.*\)'\$/\1/"; }

if [[ ! -S $XDG_RUNTIME_DIR/bus ]]; then
  echo "MISSING    no session bus at $XDG_RUNTIME_DIR/bus; log in to the desktop first" >&2
  exit 1
fi

current_ssh=$(sed -n 's/^Port \([0-9]*\)$/\1/p' "$ssh_conf" 2> /dev/null || true)
current_rdp=$(rdp_get port)
# 3389 is GNOME's default, so it was not chosen here
[[ $current_rdp == 3389 ]] && current_rdp=
ssh_port=${SSH_PORT:-${current_ssh:-$(random_port)}}
rdp_port=${RDP_PORT:-${current_rdp:-$(random_port "$ssh_port")}}
for p in "$ssh_port" "$rdp_port"; do
  if ! valid_port "$p"; then
    echo "INVALID    port $p (1024-65535)" >&2
    exit 2
  fi
done
if [[ $ssh_port == "$rdp_port" ]]; then
  echo "INVALID    SSH and RDP share port $ssh_port" >&2
  exit 2
fi

fill() {
  local content
  content=$(< "$src/$1")
  content=${content//@SSH_PORT@/"$ssh_port"}
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

# --- Firewall: open the new SSH port before sshd moves to it; RDP stays closed

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

# --- Earlier versions ran a separate TigerVNC XFCE session for this user. A second
# desktop of the same user shares its systemd user manager and session bus with
# GNOME, which broke GNOME's unlock, so remove it.

vnc_users=/etc/tigervnc/vncserver.users
while read -r n; do
  [[ -z $n ]] && continue
  if $dry; then
    echo "would remove TigerVNC display :$n"
  else
    sudo systemctl disable --now --quiet "tigervncserver@:$n.service" 2> /dev/null || true
    sudo sed -i "/^ *:$n=$user *\$/d" "$vnc_users"
    echo "removed    TigerVNC display :$n"
  fi
done < <(sed -n "s/^ *:\([0-9]*\)=$user *\$/\1/p" "$vnc_users" 2> /dev/null || true)
for old in "$HOME/.vnc/tigervnc.conf" /etc/polkit-1/rules.d/50-dotfiles-colord.rules; do
  if [[ ! -f $old ]] || ! head -1 "$old" | grep -qF "$marker"; then
    continue
  fi
  if $dry; then
    echo "would remove $old"
  else
    sudo rm -f "$old"
    echo "removed    $old"
  fi
done
# The VNC password is stored with a reversible cipher; it has no other use here
if [[ -f $HOME/.vnc/passwd ]]; then
  if $dry; then
    echo "would remove ~/.vnc/passwd"
  else
    rm -f "$HOME/.vnc/passwd"
    echo "removed    ~/.vnc/passwd"
  fi
fi
leftover=$(for p in tigervnc-standalone-server tigervnc-tools xfce4 xfce4-terminal; do
  if dpkg-query -W -f='${db:Status-Status}' "$p" 2> /dev/null | grep -qx installed; then
    echo "$p"
  fi
done | paste -sd ' ' -)

# --- RDP: GNOME Remote Desktop shares the logged-in screen. ufw keeps its port
# closed, so it is reached only through SSH.

rdp_changed=false
rdp_set() {
  local key=$1 value=$2
  if [[ $(rdp_get "$key") == "$value" ]]; then
    return
  fi
  rdp_changed=true
  if $dry; then
    echo "would set  $rdp_schema $key $value"
  else
    gsettings set "$rdp_schema" "$key" "$value"
    echo "set        $rdp_schema $key $value"
  fi
}

if [[ -s $rdp_dir/rdp-tls.key && -s $rdp_dir/rdp-tls.crt ]]; then
  echo "ok         $rdp_dir/rdp-tls.crt"
elif $dry; then
  echo "would create a self-signed certificate in $rdp_dir"
else
  mkdir -p "$rdp_dir"
  (umask 077 && openssl req -x509 -newkey rsa:4096 -nodes -days 3650 -subj "/CN=$host" \
    -keyout "$rdp_dir/rdp-tls.key" -out "$rdp_dir/rdp-tls.crt" 2> /dev/null)
  echo "created    $rdp_dir/rdp-tls.crt"
fi
rdp_set tls-key "$rdp_dir/rdp-tls.key"
rdp_set tls-cert "$rdp_dir/rdp-tls.crt"
rdp_set port "$rdp_port"
rdp_set negotiate-port false
rdp_set view-only false
rdp_set enable true
$rdp_changed || echo "ok         $rdp_schema"

# Credentials live in the login keyring, which the desktop login unlocks
creds=$(timeout 20 grdctl status 2> /dev/null | sed -n 's/^\s*Username: //p')
if [[ $creds == "(hidden)" ]]; then
  echo "ok         RDP credentials"
elif $dry; then
  echo "would ask  for an RDP password"
else
  if [[ -t 0 ]]; then
    read -rsp "RDP password for $user (not the login password): " pw
    echo
    read -rsp "Again: " pw2
    echo
    if [[ $pw != "$pw2" ]]; then
      echo "FAILED     passwords differ; run this installer again" >&2
      exit 1
    fi
  else
    read -r pw || true
  fi
  if [[ -z ${pw-} ]]; then
    echo "MISSING    RDP password; run this installer in a terminal" >&2
    failed=1
  # grdctl 46 takes the password only as an argument
  elif timeout 20 grdctl rdp set-credentials "$user" "$pw" 2> /dev/null; then
    echo "set        RDP credentials"
  else
    echo "FAILED     grdctl could not store credentials; is the desktop logged in?" >&2
    failed=1
  fi
  unset pw pw2
fi

unit=gnome-remote-desktop.service
if ! $dry && ((failed == 0)); then
  if $rdp_changed && systemctl --user is-active --quiet "$unit"; then
    systemctl --user restart "$unit"
  fi
  systemctl --user enable --now --quiet "$unit" 2> /dev/null
  for _ in {1..10}; do
    listening | grep -qx "$rdp_port" && break
    sleep 1
  done
  if listening | grep -qx "$rdp_port"; then
    echo "ok         RDP listening"
  else
    echo "FAILED     RDP is not listening; see linux/status.sh"
    failed=1
  fi
fi

# --- Summary

cat << EOF

SSH port $ssh_port, RDP port $rdp_port (closed by ufw; reached through SSH)
Add to ~/.ssh/config on the Mac:

  Host $host
    HostName $(hostname -I 2> /dev/null | awk '{print $1}')
    Port $ssh_port
    User $user
    IdentityFile ~/.ssh/id_ed25519_$host
    IdentitiesOnly yes

IdentitiesOnly stops ssh offering every agent key first; sshd disconnects
after six with "Too many authentication failures".
Then, on the Mac: ~/dotfiles/linux/mac-tunnel.sh $host $rdp_port
and connect Windows App to "localhost" as $user with the RDP password.
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
if [[ -n $leftover ]]; then
  cat << EOF

UNUSED     packages from the earlier VNC setup: $leftover
Remove with: sudo apt purge $leftover && sudo apt autoremove
EOF
fi
exit "$failed"
