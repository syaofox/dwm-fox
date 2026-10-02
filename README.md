# dwm-fox

A fast, focused X11 desktop for **Debian and Ubuntu Server**, built around a
heavily patched fork of suckless dwm and a managed Quickshell shell.

dwm-fox is a port of [dwm-titus](https://github.com/ChrisTitusTech/dwm-titus)
from Fedora to Debian/Ubuntu. The window manager, its patches, the Quickshell
panel and launcher, Settings, the Control Center, the theme system and the
hotkey system are unchanged from upstream; what changed is the platform. See
[`MIGRATION.md`](MIGRATION.md) for the complete, itemised difference list, and
[`NOTICE.md`](NOTICE.md) for attribution and licensing.

> Upstream dwm-titus is Fedora-only. This repository targets Ubuntu Server
> 26.04.1 LTS and newer Debian/Ubuntu releases.

---

## What you get

| Experience | What it includes |
| --- | --- |
| **A focused desktop** | Automatic tiling, nine tags, keyboard navigation, multi-monitor support, flexible fullscreen modes. |
| **Everyday essentials** | Quickshell panel with clock and tray, application launcher, Control Center, Settings, notifications, screenshots, audio, brightness and power controls. |
| **Easy discovery** | Interactive keybind viewer, guided display setup, built-in diagnostics, workstation self-heal. |
| **Personal configuration** | Live-reloading hotkeys, themes and window rules; local configuration is preserved across upgrades. |
| **One-command install** | `install.sh` resolves dependencies, builds, installs, wires up the session and verifies the result. |

> dwm-fox is an X11 desktop. A Wayland-native session is out of scope.

---

## Requirements

- Ubuntu Server 26.04.1 LTS or a current Debian release (`universe` enabled)
- An X11-capable GPU or a virtual display
- `sudo`, and outbound access to the Ubuntu archive

The installer refuses to run on any other distribution identity rather than
attempting an untested path.

### One third-party repository

Quickshell is not in the Ubuntu archive and upstream publishes no binaries, so
`install.sh` enables the official `avengemedia/danklinux` PPA — the path the
Quickshell project documents for Ubuntu. The signing key fingerprint is pinned
and verified before it is trusted
(`scripts/dwm-quickshell-repo.sh`).

The repository is only touched when Quickshell is not already installed, so
`--profile core` never enables it. To manage it directly:

```bash
scripts/dwm-quickshell-repo.sh status    # report without changing anything
scripts/dwm-quickshell-repo.sh enable    # add keyring + suite-scoped source
scripts/dwm-quickshell-repo.sh disable   # remove exactly what enable created
```

---

## Install

```bash
git clone <this-repository> dwm-fox
cd dwm-fox

# See the resolved plan first. Nothing is changed.
./install.sh --dry-run --non-interactive --profile recommended

# Then install it.
./install.sh --profile recommended
```

### Options

| Option | Effect |
| --- | --- |
| `--profile core` | X11 session, build/runtime dependencies, one terminal. No Quickshell, no third-party repository. |
| `--profile recommended` | The everyday desktop: panel, launcher, Control Center, Settings, theming, screenshots, audio, brightness, system management. |
| `--profile full` | Everything above plus optional file manager, keyring, wallpapers, display manager integration and gaming. |
| `--non-interactive` | Unattended defaults, no prompts. Implied when stdin or stdout is not a TTY. |
| `--yes` | Accept the interactive summary. |
| `--enable-display-manager` | Install and enable LightDM so the session is selectable at the login screen. |
| `--no-display-manager` | Never install or enable a display manager. `startx` only. |
| `--no-linger` | Do not enable systemd linger for your user. |
| `--enable-gaming` | Approve enabling Ubuntu's `multiverse` component so Steam can be installed (`full` profile only). |
| `--install-herdr` | Also install the verified Herdr terminal workspace. Off by default. |
| `--dry-run` | Print the resolved plan and exit without changing anything. |

`install.sh` runs as a **normal user** and escalates only for package
installation and system-wide file placement. It is idempotent: re-running does
not duplicate services, reset your choices, or overwrite your configuration.

### What the installer changes

Outside `${PREFIX}` (default `/usr/local`) and your home directory:

| Path | Purpose |
| --- | --- |
| `/usr/share/xsessions/dwm.desktop` | session entry for display managers |
| `/etc/xdg/autostart/dwm-fox-session.desktop` | activates the systemd graphical-session targets |
| `/etc/pam.d/xsession` | gives a PAM-driven X login a systemd user session |
| `/var/lib/dwm-fox/` | root-owned state directory |

And on your account:

- membership of `video`, `render`, `input` and `audio`
- `loginctl enable-linger` so `systemd --user` exists outside a display-manager
  login

None of these are secret, and every one of them is reversed by
`scripts/dwm-session-setup.sh uninstall`.

---

## Start a session

### From a TTY (default)

```bash
startx
```

`startx` reads `~/.xinitrc`, which runs the installed session launcher. The
launcher creates the session environment Ubuntu Server does not provide
(`XDG_RUNTIME_DIR`, `XDG_DATA_HOME`, a session D-Bus) and then execs dwm.

### From a display manager

```bash
sudo systemctl enable --now lightdm
```

Select the **`dwm-fox`** session at the login screen. The same launcher runs, so
the two paths behave identically.

### If the session does not start

Run it from a TTY so you can see the error:

```bash
startx
```

Then collect a report:

```bash
dwm-diagnostics
bash scripts/dwm-session-setup.sh status
```

---

## First steps

**Super** is the Windows key on most keyboards.

| Action | Keybind |
| --- | --- |
| Application launcher | <kbd>Super</kbd> + <kbd>R</kbd> |
| Terminal | <kbd>Super</kbd> + <kbd>X</kbd> |
| Control Center | <kbd>Super</kbd> + <kbd>F1</kbd> |
| Interactive keybind viewer | <kbd>Super</kbd> + <kbd>/</kbd> |
| Close the focused window | <kbd>Super</kbd> + <kbd>Q</kbd> |
| Switch tag | <kbd>Super</kbd> + <kbd>1</kbd>–<kbd>9</kbd> |
| Power menu | <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>Q</kbd> |

## Customise

Personal settings live under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dwm-fox/
```

`hotkeys.toml`, `themes.toml` and `window-rules.toml` reload when saved.
Compile-time preferences live in the user-owned `config.h`, which the installer
preserves.

`${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` is managed by dwm-fox and is
replaced wholesale on install, so stale shell code cannot survive an upgrade.

Fifteen GTK palettes (`Dwm-nord`, `Dwm-dracula`, …) are installed system-wide
under `/usr/share/themes`, with matching `qt5ct`/`qt6ct` colour profiles, plus
the Capitaine cursor themes.

---

## Uninstall

```bash
# 1. Revert the session integration (groups are left alone, and it says so).
sudo bash scripts/dwm-session-setup.sh uninstall

# 2. Remove the installed files.
sudo make uninstall

# 3. Remove the Quickshell repository.
sudo bash scripts/dwm-quickshell-repo.sh disable
```

`make uninstall` removes the dwm binary, the installed commands and privileged
helpers, the man page, the session entry, the bundled themes, the cursors and the
recorded installation manifest.

To also drop group membership:

```bash
sudo gpasswd -d "$USER" video
sudo gpasswd -d "$USER" render
sudo gpasswd -d "$USER" input
sudo gpasswd -d "$USER" audio
sudo loginctl disable-linger "$USER"
```

Your own configuration under `~/.config/dwm-fox`, `~/.config/quickshell` and
`~/.local/share/dwm-fox` is never removed automatically. Delete it by hand once
you are sure you do not want it back.

---

## Troubleshooting

Start with the built-in report:

```bash
dwm-diagnostics
```

Then the session report:

```bash
bash scripts/dwm-session-setup.sh status
```

### The panel, launcher or Settings do not open

`quickshell --version` succeeding does not mean the shell can load. Ubuntu ships
each Qt Quick QML module as a separate package and the `quickshell` package does
not depend on them.

```bash
apt-get install qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-window \
  qml6-module-qtquick-templates qml6-module-qtquick-dialogs \
  qml6-module-qtquick-shapes qml6-module-qtqml-workerscript \
  qml6-module-qt-labs-platform qml6-module-qtmultimedia
```

`tests/test-qt-runtime-modules.sh` keeps that list honest against the imports in
`config/quickshell/`.

To see Quickshell's own error directly:

```bash
quickshell --path "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml"
```

### `startx` has no panel, tray or notifications

The session has no `systemd --user` manager, so nothing that needs one can run.

```bash
loginctl show-user "$USER" -p Linger     # expect: Linger=yes
sudo loginctl enable-linger "$USER"      # fix it
```

If `Linger=yes` and it is still missing, check that `/etc/pam.d/xsession`
exists and includes `common-session`.

### Xorg cannot open the GPU or input devices

Under `startx` there is no logind seat session, so Ubuntu's dynamic device ACLs
are not applied.

```bash
id -nG | tr ' ' '\n' | grep -xE 'video|render|input'   # expect all three
sudo usermod -aG video,render,input "$USER"            # fix it, then log out and back in
```

### Settings reports that unattended updates are unsupported

The system-management backend refuses unattended updates unless the installed
PackageKit meets a documented floor and the running daemon matches it. See
[`MIGRATION.md` §5](MIGRATION.md#5-rpmdnf-code-paths--dpkgapt). To see the exact
reason:

```bash
DWM_SYSTEM_MANAGEMENT_DEBUG=1 dwm-system-management snapshot-updates
```

Usual fix:

```bash
sudo apt-get install --only-upgrade packagekit
sudo systemctl restart packagekit
```

### A display manager appeared even though I asked for none

`light-locker` has a hard `Depends: lightdm` on Ubuntu and its postinst enables
the service, so it is opt-in in dwm-fox. If you installed `light-locker` by
hand:

```bash
sudo apt-get remove light-locker
sudo systemctl disable --now lightdm
sudo systemctl set-default multi-user.target   # if you want no graphical boot at all
```

### Build fails on a missing pkg-config module

```bash
scripts/check-deps.sh
```

It lists the package profile behind each check.

### Getting the real error from a system helper

```bash
DWM_SYSTEM_MANAGEMENT_DEBUG=1 dwm-system-management snapshot-core
```

---

## Build from source

```bash
make clean
make                 # build only
sudo make install    # requires root; writes under ${PREFIX}
sudo make uninstall
```

`sudo make install` matters: the `install-cursors` and `install-app-themes`
targets write under `${DATADIR}` without escalating on their own. `install.sh`
always invokes `sudo make install`.

Useful variables: `PREFIX`, `DESTDIR`, `MANPREFIX`, `XSESSIONSDIR`,
`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `CC`, `CFLAGS`,
`CPPFLAGS`, `LDFLAGS`.

---

## Tests

```bash
make check-platform              # distribution gate and package-manager wiring
make check-package-map           # dependency map completeness and drift
make check-quickshell-session-setup   # session launcher, session setup, PPA, QML modules
```

Or directly:

```bash
bash   tests/test-platform.sh
bash   tests/test-package-map.sh
bash   tests/test-qt-runtime-modules.sh
bash   tests/test-dwm-session.sh
bash   tests/test-quickshell-repo.sh
python3 tests/test-packagekit-floor.py
sudo   bash tests/test-session-setup.sh     # needs root: creates a fixture account
```

`tests/RESULTS.md` records what was verified on a real Ubuntu Server 26.04.1
VM, including the tests that do not pass and why.

The upstream suite is wired into `make check`.

---

## Known gaps

These are deliberate, and each is documented in
[`MIGRATION.md`](MIGRATION.md):

- **No ISO or image builder.** dwm-fox is an existing-system installer only.
- **No first-boot update center.** Upstream's `dwm-initial-update` measured DNF
  mirror throughput through `libdnf5`; there is no apt equivalent implemented
  here.
- **Screen locking is opt-in**, because `light-locker` pulls in and enables
  LightDM on Ubuntu.
- **Reduced coverage of the terminal update-recovery path.** The `dnf5` executor
  became `apt-get`, and the 68 KB test written against `dnf5` was dropped rather
  than rewritten.
- **Fedora gaming repositories** are replaced by Ubuntu's `multiverse` component,
  and 32-bit Mangohud/GameMode variants do not exist.

---

## Licence and attribution

dwm and its patches are MIT / X Consortium licensed; see [`LICENSE`](LICENSE).
This port is a derivative work of
[dwm-titus](https://github.com/ChrisTitusTech/dwm-titus) by Chris Titus Tech.
Full attribution is in [`NOTICE.md`](NOTICE.md).