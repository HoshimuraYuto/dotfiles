# A fresh Ubuntu 24.04 with systemd, so ssh.socket, ufw and the VNC unit run as on a real machine
FROM ubuntu:24.04
# The base image blocks service starts in package scripts (policy-rc.d); a real install does not
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv sudo dbus iproute2 openssh-client \
  && rm -rf /var/lib/apt/lists/* \
  && rm -f /usr/sbin/policy-rc.d
RUN useradd -m -s /bin/bash -G sudo tester \
  && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
CMD ["/sbin/init"]
