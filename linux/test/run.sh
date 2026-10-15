#!/usr/bin/env bash
# Runs linux/install.sh in a systemd Ubuntu container ("host") with a headless GNOME Shell
# standing in for the desktop login, and checks it from a second container ("client").
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
# UBUNTU=24.04 tests the older LTS; the default is the current one
ubuntu=${UBUNTU:-26.04}
tag=dotfiles-linux-test:$ubuntu
net=dotfiles-linux-test
host=dotfiles-linux-host
client=dotfiles-linux-client

cleanup() {
  docker rm -f "$host" "$client" > /dev/null 2>&1 || true
  docker network rm "$net" > /dev/null 2>&1 || true
}
# KEEP=1 leaves the containers running for inspection
[[ ${KEEP-} == 1 ]] || trap cleanup EXIT
cleanup

docker build -q --build-arg UBUNTU="$ubuntu" -t "$tag" "$here" > /dev/null
echo "# Ubuntu $ubuntu"
docker network create "$net" > /dev/null
for name in "$host" "$client"; do
  docker run -d --name "$name" --hostname "$name" --network "$net" \
    --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock -v "$repo:/dotfiles:ro" "$tag" > /dev/null
done
sleep 3

# docker exec has no login session, so point at the user bus the desktop login would provide
user_env='export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus;'
on() { docker exec -u tester "$host" bash -c "$user_env $1"; }
as_root() { docker exec "$host" bash -c "$1"; }
from_client() { docker exec -u tester "$client" bash -c "$1"; }
pass=0
fail=0
# Waits inside a check end with "exit 0" on success and "exit 1" after the loop:
# a bare for loop returns the status of its last sleep, which always passes.
check() {
  # pipefail would count a producer killed by SIGPIPE (grep -q stops reading early) as a failure
  if (
    set +o pipefail
    eval "$2"
  ) > /dev/null 2>&1; then
    echo "pass  $1"
    pass=$((pass + 1))
  else
    echo "FAIL  $1"
    fail=$((fail + 1))
  fi
}

echo "## preview on a fresh machine"
check "preview lists missing packages" "on '/dotfiles/linux/install.sh -n' | grep -q '^would install'"

echo "## desktop login: user manager, unlocked keyring, GNOME Shell"
as_root 'echo tester:test-password | chpasswd && loginctl enable-linger tester'
sleep 2
on 'echo test-password | gnome-keyring-daemon --unlock --components=secrets > /dev/null'
on 'systemd-run --user --unit=gnome-shell gnome-shell --headless --wayland --virtual-monitor 1280x800' > /dev/null 2>&1
check "GNOME Shell is up" \
  "for _ in {1..30}; do on 'busctl --user status org.gnome.Mutter.RemoteDesktop' && exit 0; sleep 1; done; exit 1"

echo "## an earlier version's TigerVNC session, to be removed"
as_root 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends tigervnc-standalone-server tigervnc-tools' > /dev/null 2>&1
as_root 'echo ":10=tester" >> /etc/tigervnc/vncserver.users'
on 'mkdir -p ~/.vnc && printf "# Managed by dotfiles linux/install.sh\n\$rfbport = 25901;\n\$localhost = \"yes\";\n1;\n" > ~/.vnc/tigervnc.conf && echo vncpass1 | tigervncpasswd -f > ~/.vnc/passwd'
as_root 'systemctl enable --now tigervncserver@:10.service' > /dev/null 2>&1

echo "## first run"
out=$(on 'echo rdp-pass1 | /dotfiles/linux/install.sh' 2>&1) || true
ssh_port=$(sed -n 's/^SSH port \([0-9]*\), RDP port.*/\1/p' <<< "$out")
rdp_port=$(sed -n 's/^SSH port [0-9]*, RDP port \([0-9]*\) .*/\1/p' <<< "$out")
echo "ssh $ssh_port, rdp $rdp_port"
check "ports in 10000-32767 and distinct" \
  "((ssh_port >= 10000 && ssh_port <= 32767 && rdp_port >= 10000 && rdp_port <= 32767 && ssh_port != rdp_port))"
check "sshd listens on the new port only" \
  "as_root 'ss -ltnH' | grep -q ':$ssh_port ' && ! as_root 'ss -ltnH' | grep -q ':22 '"
check "RDP listens on its port" "as_root 'ss -ltnH' | grep -q ':$rdp_port '"
check "RDP allows control" "[[ \$(on 'gsettings get org.gnome.desktop.remote-desktop.rdp view-only') == false ]]"
check "RDP credentials stored" "on 'grdctl status' | grep -q 'Username: (hidden)'"
check "ufw active, only the SSH port open" \
  "[[ \$(as_root 'ufw status' | grep -cE 'ALLOW|LIMIT') == 2 ]] && as_root 'ufw status' | grep -q '$ssh_port/tcp *LIMIT'"
check "summary warns that password login is on" "grep -q 'Password login is still on' <<< \"\$out\""
check "TigerVNC session removed" \
  "! as_root 'systemctl is-enabled tigervncserver@:10.service' && ! as_root 'grep -q tester /etc/tigervnc/vncserver.users'"
check "VNC files removed" "on '[[ ! -e ~/.vnc/tigervnc.conf && ! -e ~/.vnc/passwd ]]'"
check "summary lists the unused VNC packages" "grep -q '^UNUSED .*tigervnc-standalone-server' <<< \"\$out\""
ext=allowlockedremotedesktop@kamens.us
# gnome-extensions info knows the extension only after the shell has loaded it, so read the files
check "lock-screen extension installed and enabled" \
  "on 'grep -q \"\\\"version\\\": 17\" ~/.local/share/gnome-shell/extensions/$ext/metadata.json' && on 'gsettings get org.gnome.shell enabled-extensions' | grep -qF \"'$ext'\""
check "summary asks to log in again to load it" "grep -q '^LOGIN ' <<< \"\$out\""
# What the next login does: restart the shell, which then loads the extension
on 'systemctl --user restart gnome-shell'
check "extension active after the shell restarts" \
  "for _ in {1..30}; do on \"gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Extensions.GetExtensionInfo $ext\" | grep -q \"'state': <1.0>\" && exit 0; sleep 1; done; exit 1"

echo "## from another machine"
from_client 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519 <<< y > /dev/null'
check "port 22 is closed" "! from_client 'timeout 3 bash -c \"</dev/tcp/$host/22\"'"
check "RDP port is not reachable directly" "! from_client 'timeout 3 bash -c \"</dev/tcp/$host/$rdp_port\"'"
as_root "mkdir -p ~tester/.ssh && chown tester: ~tester/.ssh"
docker exec -u tester "$client" cat /home/tester/.ssh/id_ed25519.pub | docker exec -i -u tester "$host" bash -c 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
# ssh keeps the first -p it sees, so the port is not part of the shared options
base_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
ssh_opts="$base_opts -p $ssh_port"
check "key login on the new port" "from_client 'ssh $ssh_opts -o BatchMode=yes tester@$host true'"

# Connects through an SSH tunnel with password $1 and prints the client's exit code:
# 124 means it was still connected when timeout stopped it; anything else, refused or dropped
rdp() {
  from_client "ssh $ssh_opts -f -o ExitOnForwardFailure=yes -L 13389:localhost:$rdp_port tester@$host sleep 20
    pgrep Xvfb > /dev/null || { Xvfb :50 -screen 0 1400x900x24 > /dev/null 2>&1 & sleep 1; }
    DISPLAY=:50 timeout 12 xfreerdp3 /v:127.0.0.1:13389 /u:tester /p:$1 /cert:ignore /size:1280x800 > /tmp/rdp.log 2>&1 &
    sleep 10; DISPLAY=:50 xwd -root -silent | convert xwd:- /tmp/rdp.png; wait \$!; echo \$?"
}
check "RDP through an SSH tunnel stays connected" "[[ \$(rdp rdp-pass1) == 124 ]]"
docker cp "$client:/tmp/rdp.png" "${TMPDIR:-/tmp}/dotfiles-linux-rdp.png" > /dev/null 2>&1 || true
check "RDP refuses a wrong password" "[[ \$(rdp wrong-pass) != 124 ]]"

echo "## status report"
status=$(on '/dotfiles/linux/status.sh')
check "status reports no problem" "! grep -q '^NG' <<< \"\$status\""
check "status hides ports, address, host and user" \
  "! grep -qE '\\b($ssh_port|$rdp_port)\\b|$host|tester|172\\.' <<< \"\$status\""
on 'systemctl --user stop gnome-remote-desktop.service'
check "status reports a stopped RDP server" \
  "on '/dotfiles/linux/status.sh' | grep -q '^NG *RDP: nothing listens on <RDP_PORT>'"
on 'systemctl --user start gnome-remote-desktop.service'

echo "## second run, after a key was added"
out2=$(on '/dotfiles/linux/install.sh' 2>&1)
check "ports are kept" "grep -q '^SSH port $ssh_port, RDP port $rdp_port ' <<< \"\$out2\""
check "password login is off" "as_root 'sshd -T' | grep -qx 'passwordauthentication no'"
check "password login is refused" \
  "! from_client 'ssh $ssh_opts -o BatchMode=yes -o PreferredAuthentications=password tester@$host true'"
check "key login still works" "from_client 'ssh $ssh_opts -o BatchMode=yes tester@$host true'"
check "third run changes nothing" \
  "! on '/dotfiles/linux/install.sh' | grep -qE '^(wrote|set|created|removed|installed|enabled|LOGIN|would)'"

echo "## SSH_PORT moves the port and closes the old one"
new_port=$((ssh_port == 20000 ? 20001 : 20000))
on "SSH_PORT=$new_port /dotfiles/linux/install.sh" > /dev/null
# ufw's limit rule rejects a sixth connection within 30 s from the same client
sleep 31
check "sshd moved" "from_client 'ssh $base_opts -o BatchMode=yes -p $new_port tester@$host true'"
check "old port rule removed" "! as_root 'ufw status' | grep -q '^$ssh_port/tcp'"

echo "## an unmanaged sshd file is a conflict"
as_root 'mv /etc/ssh/sshd_config.d/50-dotfiles.conf /tmp/ && echo "Port 2222" > /etc/ssh/sshd_config.d/50-dotfiles.conf'
check "reported, not replaced" \
  "{ on 'SSH_PORT=$new_port /dotfiles/linux/install.sh' || true; } | grep -q '^CONFLICT' && as_root 'grep -qx \"Port 2222\" /etc/ssh/sshd_config.d/50-dotfiles.conf'"

echo
echo "$pass passed, $fail failed"
((fail == 0))
