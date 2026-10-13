# Linux

Minimal setup for an Ubuntu 24.04 desktop reached from a Mac on the same LAN:
the packages in [`packages.txt`](packages.txt), ufw, SSH and VNC.

On a fresh machine:

```sh
sudo apt install -y git
git clone repository < this > ~/dotfiles
~/dotfiles/linux/install.sh -n # preview
~/dotfiles/linux/install.sh
```

Run it as the desktop user, not root. It:

- installs the missing packages with `apt-get`;
- enables ufw, denying incoming traffic except the SSH port (rate-limited);
- moves SSH to a random port in 10000-32767 through
  `/etc/ssh/sshd_config.d/50-dotfiles.conf`, without root login, and with
  password login only until `~/.ssh/authorized_keys` holds a key;
- runs a TigerVNC XFCE session as `tigervncserver@:1`, listening on another
  random port on localhost only, so it is reachable only through SSH.

Ports are chosen on the first run and read back from the generated files after
that; set `SSH_PORT` or `VNC_PORT` to choose them. The installer ends by
printing the `~/.ssh/config` entry for the Mac. Port 22 stops listening once
the new port is active; keep the current session open until a login on the new
port works.

Then, on the Mac, add that entry to `~/.ssh/config` before connecting. It
names one key with `IdentitiesOnly yes`: without it, ssh first offers every
key in the agent (1Password, for example), and sshd disconnects after six with
"Too many authentication failures". Create the key and copy it over:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<host>
ssh-copy-id -i ~/.ssh/id_ed25519_<host>.pub <host>
```

and run `install.sh` again to turn off password login.

The VNC session is a separate XFCE desktop, not the screen shown on the
monitor: GNOME's Wayland session does not run inside Xtigervnc. Its password is
asked once with `tigervncpasswd`; VNC uses only the first 8 characters. A polkit
rule lets administrators register the VNC screen with colord, which otherwise
asks for a password on every login.

When something does not connect, run `linux/status.sh` on the machine (or
`ssh <host> '~/dotfiles/linux/status.sh' | pbcopy` from the Mac). It marks each
check `ok` or `NG`, appends the VNC logs, and replaces ports, addresses, the
host name and the user name, so the output can be pasted as is.

An existing file at either config path that was not written by this installer
is reported as a conflict, not replaced.

## Requirements

Installed separately, not by `install.sh`.

|                     | Used by      |
| ------------------- | ------------ |
| Ubuntu 24.04, sudo  | `install.sh` |
| git                 | cloning      |
| Docker (on the Mac) | `test/`      |

## Checks

```sh
linux/test/run.sh
```

builds a systemd Ubuntu 24.04 container, runs the installer twice and connects
over SSH from a second container.
