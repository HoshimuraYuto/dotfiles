# A fresh Ubuntu 24.04 with systemd, so ssh.socket, ufw and user services run as on a real machine.
# GNOME Shell (headless), the keyring and an RDP client stand in for the desktop login and the Mac.
FROM ubuntu:24.04
# The base image blocks service starts in package scripts (policy-rc.d); a real install does not
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    systemd systemd-sysv sudo dbus dbus-user-session iproute2 openssh-client \
    gnome-shell gnome-keyring libglib2.0-bin freerdp3-x11 xvfb x11-apps imagemagick \
  && rm -rf /var/lib/apt/lists/* \
  && rm -f /usr/sbin/policy-rc.d
RUN useradd -m -s /bin/bash -G sudo tester \
  && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
CMD ["/sbin/init"]
