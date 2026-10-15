# Linux

Minimal setup for an Ubuntu 24.04 or 26.04 desktop reached from a Mac on the same LAN:
the packages in [`packages.txt`](packages.txt), ufw, SSH and remote desktop.

On a fresh machine, logged in to the desktop:

```sh
sudo apt install -y git
git clone https://github.com/HoshimuraYuto/dotfiles ~/dotfiles
~/dotfiles/linux/install.sh -n # preview
~/dotfiles/linux/install.sh
```

Run it as the desktop user, not root, while that user is logged in to GNOME
(over SSH is fine). It:

- installs the missing packages with `apt-get`;
- enables ufw, denying incoming traffic except the SSH port (rate-limited);
- moves SSH to a random port in 10000-32767 through
  `/etc/ssh/sshd_config.d/50-dotfiles.conf`, without root login, and with
  password login only until `~/.ssh/authorized_keys` holds a key;
- turns on GNOME Remote Desktop (RDP) for the logged-in screen on another
  random port, which ufw keeps closed, so it is reachable only through SSH. It
  asks once for an RDP password, kept in the login keyring.

Ports are chosen on the first run and read back afterwards; set `SSH_PORT` or
`RDP_PORT` to choose them. The installer ends by printing the `~/.ssh/config`
entry for the Mac. Port 22 stops listening once the new port is active; keep
the current session open until a login on the new port works.

## On the Mac

Add the printed entry to `~/.ssh/config` before connecting. It names one key
with `IdentitiesOnly yes`: without it, ssh first offers every key in the agent
(1Password, for example), and sshd disconnects after six with "Too many
authentication failures". Create the key and copy it over:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_<host>
ssh-copy-id -i ~/.ssh/id_ed25519_<host>.pub <host>
```

and run `install.sh` again to turn off password login. Then:

```sh
~/dotfiles/linux/mac-tunnel.sh <host> <rdp port>
```

It registers a launchd job that listens on `localhost:3389` and starts
`ssh -W` for each connection, so nothing runs while no client is connected and
no terminal has to stay open. Connect
[Windows App](https://apps.apple.com/app/windows-app/id1295203466) to
`localhost` with the user name and the RDP password. `--remove <host>` deletes
the job. After reinstalling Linux the host key changes and ssh refuses to
forward; the client only sees a failed connection, so rerun `mac-tunnel.sh`,
which reports it.

RDP shares the screen on the monitor; it cannot start a session, so the user
must be logged in. GNOME stops remote access while the screen is locked;
`install.sh` installs the
[Allow Locked Remote Desktop](https://extensions.gnome.org/extension/4338/allow-locked-remote-desktop/)
extension (pinned version and checksum) so a client reaches the lock screen and
unlocks it with the login password. That also unlocks the monitor. The shell
loads the extension at the next login.

FreeRDP 3.32.0 and 3.32.1 (Ubuntu's updates as of October 2026) stall Windows
App at "Securing connection to remote PC"
([FreeRDP#13549](https://github.com/FreeRDP/FreeRDP/issues/13549),
[LP#2168823](https://bugs.launchpad.net/ubuntu/+source/freerdp3/+bug/2168823)).
FreeRDP 3.32.2 fixes it; until Ubuntu ships it, rebuild Ubuntu's `freerdp3`
with upstream commit `cbb6a73d1` and install `libfreerdp3-3`,
`libfreerdp-server3-3` and `libwinpr3-3`.

Earlier versions of this installer ran a separate TigerVNC XFCE session. A
second desktop of the same user shares GNOME's user services and broke the
GNOME unlock, so `install.sh` now removes it and lists its packages for
`apt purge`.

When something does not connect, run `linux/status.sh` on the machine (or
`ssh <host> '~/dotfiles/linux/status.sh' | pbcopy` from the Mac). It marks each
check `ok` or `NG`, appends the RDP log, and replaces ports, addresses, the host
name and the user name, so the output can be pasted as is.

An existing sshd config file that was not written by this installer is reported
as a conflict, not replaced.

## Requirements

Installed separately, not by `install.sh`.

|                                     | Used by      |
| ----------------------------------- | ------------ |
| Ubuntu 24.04 or 26.04 desktop, sudo | `install.sh` |
| git                                 | cloning      |
| Windows App (on the Mac)            | connecting   |
| Docker (on the Mac)                 | `test/`      |

## Checks

```sh
linux/test/run.sh
```

builds a systemd Ubuntu 26.04 container (`UBUNTU=24.04` for the older LTS) with a headless GNOME Shell, runs the
installer over an earlier VNC setup, and connects over SSH and RDP from a second
container. `mac-tunnel.sh` needs launchd, so it is not covered; it was
checked by hand against the same container.
