#!/usr/bin/env bash
# Runs linux/install.sh in a systemd Ubuntu container ("host") and checks it from a second one ("client").
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/../.." && pwd)
tag=dotfiles-linux-test
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

docker build -q -t "$tag" "$here" > /dev/null
docker network create "$net" > /dev/null
for name in "$host" "$client"; do
  docker run -d --name "$name" --hostname "$name" --network "$net" \
    --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock -v "$repo:/dotfiles:ro" "$tag" > /dev/null
done
sleep 3

on() { docker exec -u tester "$host" bash -c "$1"; }
as_root() { docker exec "$host" bash -c "$1"; }
from_client() { docker exec -u tester "$client" bash -c "$1"; }
pass=0
fail=0
check() {
  if eval "$2" > /dev/null 2>&1; then
    echo "pass  $1"
    pass=$((pass + 1))
  else
    echo "FAIL  $1"
    fail=$((fail + 1))
  fi
}

echo "## preview on a fresh machine"
check "preview lists missing packages" "on '/dotfiles/linux/install.sh -n' | grep -q '^would install'"

echo "## first run"
as_root 'echo tester:test-password | chpasswd'
on '/dotfiles/linux/install.sh' > /dev/null 2>&1 || true
# tigervnc-tools is installed by the run above, so the password can be written only now
on 'echo vncpass1 | tigervncpasswd -f > ~/.vnc/passwd && chmod 600 ~/.vnc/passwd'
out=$(on '/dotfiles/linux/install.sh' 2>&1)
ssh_port=$(sed -n 's/^SSH port \([0-9]*\), VNC port.*/\1/p' <<< "$out")
vnc_port=$(sed -n 's/^SSH port [0-9]*, VNC port \([0-9]*\) .*/\1/p' <<< "$out")
echo "ssh $ssh_port, vnc $vnc_port"
check "ports in 10000-32767 and distinct" \
  "((ssh_port >= 10000 && ssh_port <= 32767 && vnc_port >= 10000 && vnc_port <= 32767 && ssh_port != vnc_port))"
check "sshd listens on the new port only" \
  "as_root 'ss -ltnH' | grep -q ':$ssh_port ' && ! as_root 'ss -ltnH' | grep -q ':22 '"
check "VNC listens on localhost only" \
  "[[ \$(as_root 'ss -ltnH' | awk '{print \$4}' | grep ':$vnc_port\$') == 127.0.0.1:$vnc_port ]]"
# The unit is up before its X session; give the session time to start
check "XFCE session runs in VNC" \
  "for _ in {1..30}; do as_root 'pgrep -u tester -x xfce4-session' && break; sleep 1; done"
check "colord does not ask for a password in the VNC session" \
  "as_root 'pkcheck --action-id org.freedesktop.color-manager.create-device --process \$(pgrep -u tester -x xfce4-session)'"
check "ufw active, only the SSH port open" \
  "[[ \$(as_root 'ufw status' | grep -cE 'ALLOW|LIMIT') == 2 ]] && as_root 'ufw status' | grep -q '$ssh_port/tcp *LIMIT'"
check "summary warns that password login is on" "grep -q 'Password login is still on' <<< \"\$out\""

echo "## from another machine"
from_client 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519 <<< y > /dev/null'
check "port 22 is closed" "! from_client 'timeout 3 bash -c \"</dev/tcp/$host/22\"'"
check "VNC port is not reachable directly" "! from_client 'timeout 3 bash -c \"</dev/tcp/$host/$vnc_port\"'"
as_root "mkdir -p ~tester/.ssh && chown tester: ~tester/.ssh"
docker exec -u tester "$client" cat /home/tester/.ssh/id_ed25519.pub | docker exec -i -u tester "$host" bash -c 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
# ssh keeps the first -p it sees, so the port is not part of the shared options
base_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
ssh_opts="$base_opts -p $ssh_port"
check "key login on the new port" "from_client 'ssh $ssh_opts -o BatchMode=yes tester@$host true'"
check "VNC answers through an SSH tunnel" \
  "from_client 'ssh $ssh_opts -f -o ExitOnForwardFailure=yes -L 5901:localhost:$vnc_port tester@$host sleep 5 && head -c 12 < /dev/tcp/127.0.0.1/5901' | grep -q '^RFB 003'"

echo "## second run, after a key was added"
out2=$(on '/dotfiles/linux/install.sh' 2>&1)
check "ports are kept" "grep -q '^SSH port $ssh_port, VNC port $vnc_port ' <<< \"\$out2\""
check "password login is off" "as_root 'sshd -T' | grep -qx 'passwordauthentication no'"
check "password login is refused" \
  "! from_client 'ssh $ssh_opts -o BatchMode=yes -o PreferredAuthentications=password tester@$host true'"
check "key login still works" "from_client 'ssh $ssh_opts -o BatchMode=yes tester@$host true'"
check "third run changes nothing" "! on '/dotfiles/linux/install.sh' | grep -qE '^(wrote|added|would)'"

echo "## SSH_PORT moves the port and closes the old one"
new_port=$((ssh_port == 20000 ? 20001 : 20000))
on "SSH_PORT=$new_port /dotfiles/linux/install.sh" > /dev/null
check "sshd moved" "from_client 'ssh $base_opts -o BatchMode=yes -p $new_port tester@$host true'"
check "old port rule removed" "! as_root 'ufw status' | grep -q '^$ssh_port/tcp'"

echo "## an unmanaged sshd file is a conflict"
as_root 'mv /etc/ssh/sshd_config.d/50-dotfiles.conf /tmp/ && echo "Port 2222" > /etc/ssh/sshd_config.d/50-dotfiles.conf'
check "reported, not replaced" \
  "{ on 'SSH_PORT=$new_port /dotfiles/linux/install.sh' || true; } | grep -q '^CONFLICT' && as_root 'grep -qx \"Port 2222\" /etc/ssh/sshd_config.d/50-dotfiles.conf'"

echo
echo "$pass passed, $fail failed"
((fail == 0))
