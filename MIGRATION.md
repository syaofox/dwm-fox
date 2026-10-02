# Migration: dwm-titus (Fedora) → dwm-fox (Debian / Ubuntu)

This document records every deliberate change made when porting dwm-titus to
Ubuntu Server 26.04.1 LTS. It is the authoritative list of what is identical to
upstream, what was rewritten, and what was removed. `README.md` covers day-to-day
usage; `tests/RESULTS.md` covers what was actually verified on a real VM.

Upstream: <https://github.com/ChrisTitusTech/dwm-titus> (MIT / X Consortium,
see `LICENSE` and `NOTICE.md`). Upstream is Fedora-only and says so explicitly;
this port keeps the code and configuration identical wherever the platform does
not force a difference.

---

## 1. Platform gate

| | Upstream | dwm-fox |
| --- | --- | --- |
| Supported OS | Fedora only | Debian / Ubuntu (`debian` family) |
| Package manager | `dnf` | `apt-get` |
| Family detection | `ID == fedora` in `/etc/os-release` | `ID` in `ubuntu debian linuxmint pop elementary`, via `scripts/dwm-distro-family.sh` |
| Release name | `dwm-titus` | `dwm-fox` |

`scripts/dwm-utils.sh` still contains the `fedora` branches and
`scripts/dwm-packages.sh` still contains the `fedora:*` profiles, so the
upstream package list remains readable and diffable. `install.sh` **refuses** to
run on Fedora and says why; those branches exist for reference and are not
exercised by this project's tests.

The installer also fails clearly for any other identity before touching the
system. `tests/test-platform.sh` asserts both directions.

---

## 2. Package name mapping

`scripts/dwm-packages.sh` gained a complete `debian:*` profile set. Every name
was verified to resolve to an installable candidate on Ubuntu 26.04.1
(`apt-cache policy`), which `tests/test-package-map.sh` re-checks.

### Build

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `pkgconf-pkg-config` | `pkgconf` | |
| `libX11-devel` | `libx11-dev` | |
| `libXft-devel` | `libxft-dev` | |
| `libXinerama-devel` | `libxinerama-dev` | |
| `libXrender-devel` | `libxrender-dev` | |
| `imlib2-devel` | `libimlib2-dev` | |
| `libxcb-devel` | `libxcb1-dev` | |
| `xcb-util-devel` | `libxcb-util-dev` | |
| `freetype-devel` | `libfreetype-dev` | |
| `fontconfig-devel` | `libfontconfig1-dev` | |
| — | `libx11-xcb-dev` | **added**: backs the `x11-xcb` pkg-config module in `config.mk` |
| — | `libxcb-res0-dev` | **added**: backs the `xcb-res` pkg-config module |

### X11 session

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `xorg-x11-server-Xorg` | `xserver-xorg` | |
| `xorg-x11-xinit` | `xinit` | |
| `xrandr`, `xset`, `xsetroot` | `x11-xserver-utils` | three commands, one package |
| `setxkbmap` | `x11-xkb-utils` | separate package on Ubuntu |
| `xinput` | `xinput` | unchanged |
| `xkbset` | `xkbset` | unchanged |
| — | `xserver-xorg-input-libinput` | replaces `xorg-x11-drv-libinput` |

### Runtime

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `procps-ng` | `procps` | |
| `xprop` | `x11-utils` | pulled in with the other X utilities |
| `dbus-x11` | `dbus-x11` | unchanged |
| `libseccomp` | `libseccomp2` | the runtime library `bwrap` links |

### Desktop

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `quickshell` (Fedora repos) | `quickshell` (PPA, see §4) | |
| `dex-autostart` | `dex` | |
| `dbus-tools` | `dbus` | `dbus-tools` does not exist on Ubuntu |
| `pipewire-pulseaudio` | `pipewire-audio` | renamed in 26.04; `pipewire-bin` added for `wpctl` |
| `libnotify` | `libnotify-bin` | the runtime library is pulled in transitively |
| `mate-polkit` | `mate-polkit` | unchanged; it does provide `lxqt-admin-user` on Ubuntu too |
| `light-locker` | `light-locker` | **moved out of the desktop profile**, see §6 |

### Qt Quick runtime — new profile

Ubuntu packages every QML module separately and the `quickshell` package does
not depend on them, because on Fedora they arrive with the Qt install that
Quickshell pulls in. Without them every QML file that imports `QtQuick.Layouts`,
`QtQuick.Controls` or `QtQuick.Window` fails to load and the shell never starts,
while `quickshell --version` still reports a healthy build.

`debian:qt-runtime` installs:

```
qml6-module-qtquick  qml6-module-qtquick-controls  qml6-module-qtquick-layouts
qml6-module-qtquick-window  qml6-module-qtquick-templates
qml6-module-qtquick-dialogs  qml6-module-qtquick-shapes
qml6-module-qtqml-workerscript  qml6-module-qt-labs-platform
qml6-module-qtmultimedia
```

`tests/test-qt-runtime-modules.sh` asserts the map against the imports actually
found in `config/quickshell/`, in both directions.

### System management

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `PackageKit-glib` | `gir1.2-packagekitglib-1.0` | the GI typelib has a different name |
| `python3-gobject` | `python3-gi` | |
| `python3-rpm` | — | dropped; `dpkg-query` replaces rpm queries |
| `libpackagekit-glib2-18` (transitive) | `libpackagekit-glib2-18` (transitive) | same name |
| `dnfdragora` | `software-properties-gtk` | Ubuntu's "Software & Updates"; `lxqt-config` has no equivalent |

### Themes and fonts

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `dconf` | `dconf-gsettings-backend` | |
| `adwaita-icon-theme` | `adwaita-icon-theme` | unchanged |
| `papirus-icon-theme` | `papirus-icon-theme` | unchanged |
| `arc-theme` | `arc-theme` | unchanged |
| `numix-gtk-theme`, `deepin-gtk-theme`, `bluebird-gtk3-theme`, `adw-gtk3-theme`, `yaru-gtk3-theme`, `yaru-gtk4-theme` | — | **not in the Ubuntu archive** |
| `google-noto-color-emoji-fonts` | `fonts-noto-color-emoji` | |
| `google-noto-sans-mono-fonts` | `fonts-noto-mono` | |
| — | `fonts-noto-core` | added, the Latin base family |

The missing GTK themes are covered by the repository's own bundled palettes in
`assets/themes/Dwm-*`, which the Makefile installs to `/usr/share/themes` for
GTK 2/3/4 plus `qt5ct`/`qt6ct` colour profiles. `Nordic` is still cloned from
upstream by `install.sh`.

### Gaming

| Fedora | Ubuntu | Note |
| --- | --- | --- |
| `steam` | `steam-installer` | `steam` is multiverse-only |
| `gamemode.x86_64`, `gamemode.i686` | `gamemode` | no multilib packages on Ubuntu |
| `mangohud.x86_64`, `mangohud.i686` | `mangohud` | same |

The 32-bit variants are intentionally absent. Steam also requires the
`multiverse` component, which is **not** enabled on a minimal server image, so
the installer asks before adding it (`--enable-gaming`, or the interactive
prompt). Upstream's equivalent gate was the Gamescope COPR plus RPM Fusion
nonfree; both are Fedora concepts and were removed.

---

## 3. Package-manager behaviour

`install_packages` on Debian runs:

```
sudo env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical \
	apt-get install -y \
	-o=Dpkg::Options::=--force-confdef \
	-o=Dpkg::Options::=--force-confold \
	...
```

- `DEBIAN_FRONTEND=noninteractive` so a conffile prompt cannot hang an
  unattended install.
- `--force-confdef` / `--force-confold` keep the packaged default or the existing
  file instead of opening an editor. Neither overwrites local changes.
- `package_available` uses `apt-cache policy` and requires a real `Candidate:`,
  so a virtual or absent package is treated as unavailable.
- `package_installed` (new) uses `dpkg-query -f '${db:Status-Status}'` and
  requires exactly `installed`, so config-files-only and deinstalled packages are
  correctly reported as missing.

---

## 4. Quickshell: why a third-party repository

Quickshell is the QML engine behind the panel, launcher, Control Center,
Settings and notifications. It is **not** in the Ubuntu archive, and no upstream
GitHub release has ever carried a binary asset — every release is source-only.
The Quickshell documentation points Ubuntu users at the
`avengemedia/danklinux` Personal Package Archive, which republishes the Open
Build Service `home:AvengeMedia:danklinux` project. That PPA carries
`quickshell 0.3.1ppa1` built for `resolute` (Ubuntu 26.04), which satisfies
upstream's `dwm-quickshell-version-check` gate (≥ 0.3.0).

`scripts/dwm-quickshell-repo.sh` manages it reversibly:

- the signing key is fetched from `keyserver.ubuntu.com`;
- its fingerprint is checked against the pinned value
  `45FECBE587307AAA3F0A4BE9FC44813D2A7788B7` (confirmed against the Launchpad
  PPA metadata) **before** the key is trusted or written;
- the key is dearmored to `/usr/share/keyrings/danklinux-archive-keyring.gpg`;
- the source is a deb822 stanza scoped to the running suite, in a single file at
  `/etc/apt/sources.list.d/danklinux.sources`;
- `disable` removes only what `enable` created.

`install.sh` enables it only when Quickshell is not already present, so the
`core` profile never touches a third-party repository.

The alternative — compiling Quickshell from source against Qt 6.10 — was
considered and rejected: upstream states it must be rebuilt against each Qt
release, no release publishes binaries, and the PPA is the path the Quickshell
project itself documents for Ubuntu.

---

## 5. rpm/dnf code paths → dpkg/apt

| Script | Upstream | dwm-fox |
| --- | --- | --- |
| `scripts/dwm-desktop-update` | `rpm -q --quiet` for missing packages; `ID=fedora` gate | `dpkg-query` (`dpkg-query` first, `rpm` only as a multi-boot fallback); Debian/Ubuntu identity gate |
| `scripts/dwm-desktop-update-root` | `/usr/bin/rpm -q`; `/usr/bin/dnf install -y`; rejects `.rpm` names | `/usr/bin/dpkg-query`; `/usr/bin/apt-get install -y` with the confdef/confold options; still rejects `.rpm` names |
| `scripts/dwm-update-center` | `rpm.TransactionSet`, `rpmdb.sqlite`, `require_fedora` | `dpkg-query -W -f '${binary:Package}\n'` first, rpmdb only as a fallback; `require_debian` |
| `scripts/dwm-update-center-terminal` | allowlists `/usr/bin/dnf5`; runs `dnf5 --refresh upgrade` | allowlists `/usr/bin/apt-get`; runs `sudo apt-get -o=Dpkg::Lock::Timeout=120 … dist-upgrade` |
| `scripts/dwm-system-management` | `import rpm`, `rpm.labelCompare`, Fedora security floor | `dpkg-query` + `dpkg --compare-versions` |
| `scripts/dwm-system-health` | `dnf -q --cacheonly check` | `dpkg --audit` |
| `scripts/pkg-scan.py` | `rpm -qa` | `dpkg-query -W` first, rpm only as a fallback |
| `scripts/dev-sync-install.sh` | Fedora gate + `sudo dnf install` | family gate + `apt-get` (fedora branch retained) |
| `scripts/power-management.sh` | Fedora gate for `--apply`; dnf hints | Debian/Ubuntu gate for `--apply`; apt hints |
| `scripts/xscreensaver-setup.sh` | `ID == fedora`; `sudo dnf install` | Debian/Ubuntu gate; `apt-get install` |

### Update-provider identifiers

The system-package update provider was renamed from `fedora` to `debian`, and
its phases from `fedora-executing` / `fedora-dnf` to `debian-executing` /
`debian-apt`. The rename is consistent across `scripts/dwm-update-center`,
`scripts/dwm-update-center-terminal`, `config/quickshell/updatecenter/*.qml|js`
and the provider icon (`fedora.svg` → `apt.svg`).

Incidentally, `config/quickshell/updatecenter/UpdateCenterProtocol.js` was
missing `fedora-dnf` from its `operationPhases` list while the Python side
listed it. The list now matches the Python set exactly.

### PackageKit security floor

Upstream required PackageKit `>= 1.3.5` **or** Fedora 44's `1.3.4-3.fc44`
security backport, compared with `rpm.labelCompare`. Ubuntu 26.04 ships
`1.3.4-3ubuntu1.2`, the equivalent backport for that release.

The Debian equivalent uses `dpkg --compare-versions` against a documented floor,
`DWM_PACKAGEKIT_VERSION_FLOOR` (default `1.3.4-3ubuntu1`), and:

- validates the upstream version and the Debian revision against Debian's
  character rules before comparing;
- **refuses** a revision that does not begin with a digit. Debian orders letters
  before digits, so a revision like `v1.3.4` would sort above any numeric floor
  regardless of its digits; that cannot be checked against the floor, so it is
  rejected rather than trusted. Every in-tree revision (Debian `1`, Ubuntu
  `3ubuntu1.2`) begins with a digit;
- still requires the running daemon's semantic version to agree with the
  installed package.

`tests/test-packagekit-floor.py` covers the split, the ordering, the accepted and
rejected versions, and the malformed-input guards.

### Verifying the running daemon

Upstream compared `/usr/libexec/packagekitd` against `/proc/<pid>/exe`. That
cannot work on Ubuntu: `packagekitd` runs as root and Ubuntu closes that link to
session clients, so `os.stat` fails with `EACCES` and the check could never pass.
The check is therefore:

- when `/proc/<pid>/exe` **is** readable, the inode comparison still runs
  (unchanged upstream behaviour);
- otherwise the daemon's start time is read from `/proc/<pid>/stat`, which is
  world readable, and compared against the installed image's mtime. A daemon that
  started before the installed image was written is running the pre-update
  binary and is refused.

Set `DWM_SYSTEM_MANAGEMENT_DEBUG=1` to have `dwm-system-management` print the
underlying reason when it refuses a mutation.

---

## 6. Ubuntu Server session integration (new)

This is the largest addition. Ubuntu Server has no desktop, no display manager
and no session environment, so several things that a Fedora desktop image
provides for free had to be built.

### `scripts/dwm-session` (new)

A POSIX wrapper that becomes the single dwm entry point for both `startx` and a
display manager. It repairs, in order and only when missing:

1. **`XDG_RUNTIME_DIR`** — adopted from `/run/user/$UID` when present, otherwise
   created as a private `0700` directory. Under `startx` there is no PAM session
   at all, so nothing else provides it.
2. **`XDG_DATA_HOME` / `XDG_CONFIG_HOME`** — derived from `$HOME` when unset, so
   `dwm.c` finds `$XDG_DATA_HOME/dwm-fox/scripts/autostart.sh` and the Quickshell
   config resolves.
3. **A session D-Bus** — wrapped in `dbus-run-session` only when
   `DBUS_SESSION_BUS_ADDRESS` is unset, guarded by `DWM_FOX_DBUS_WRAPPED` so the
   re-exec cannot loop. Falls back to `dbus-launch` when `dbus-run-session` is
   unavailable.

`dwm.desktop` now runs `Exec=@PREFIX@/bin/dwm-session` instead of
`Exec=@PREFIX@/bin/dwm`, because a display-manager login and a `startx` login
need different amounts of environment repair. `tests/test-dwm-session.sh` covers
all of the above without needing an X server.

### `scripts/dwm-session-setup.sh` (new)

`install|uninstall|status`, all idempotent:

| Action | Detail |
| --- | --- |
| `/var/lib/dwm-fox` | root-owned `0755` state directory |
| `video`, `render`, `input`, `audio` groups | Ubuntu normally grants these through logind's dynamic ACLs, but those apply only to a seat session. Under `startx` there is no seat session, so Xorg cannot open `/dev/dri` or libinput devices without explicit membership |
| `loginctl enable-linger` | `startx` creates no logind session, so there is no `systemd --user` manager for `wm-graphical-session.service`, PipeWire or the polkit agent. Linger keeps the user's manager running. Disable with `--no-linger`, revoke with `loginctl disable-linger` |
| `/etc/xdg/autostart/dwm-fox-session.desktop` | a second, independent activation point for `graphical-session.target` / `xdg-desktop-autostart.target`, so `/etc/xdg/autostart` entries (polkit agent, keyring, portals) run even if dwm's autostart script does not |
| `/etc/pam.d/xsession` | does not exist on Ubuntu Server, so a PAM-driven X login never gets `pam_systemd`. Created with `common-session` included; a pre-existing file is backed up to `/var/lib/dwm-fox/session-setup-backup/` first and restored by `uninstall` |
| gnome-keyring PAM | registered with `pam-auth-update` when the module is present |

Nothing here touches the bootloader, SSH, the firewall, AppArmor, SELinux, or the
systemd default target. Every path is a variable so
`tests/test-session-setup.sh` can redirect the whole tree at a sandbox root and
run without root.

### Display manager

`startx` is the default and needs no display manager. `--enable-display-manager`
installs and enables LightDM; `--no-display-manager` never touches it; the
default (`ask`) prompts only on an interactive run with the `full` profile. The
installer never changes the systemd default target beyond enabling LightDM when
it is explicitly approved.

### `light-locker` is opt-in — important

The Ubuntu `light-locker` package has a **hard `Depends: lightdm`**, and its
postinst enables the service. Installing it therefore installs *and enables* a
display manager, which silently defeats `--no-display-manager` and changes what
starts at the next boot on a machine whose default target is `graphical.target`.

`light-locker` was therefore moved out of the `debian:desktop` profile into its
own `debian:screenlock-optional` profile. `install.sh` installs it only when a
display manager has been accepted, and otherwise prints exactly why it was
skipped. `tests/test-package-map.sh` asserts it never appears in `desktop`,
`recommended`, `required` or `full`.

---

## 7. Removed, and why

### Fedora image / factory workflow

No Ubuntu equivalent exists, and none of it is needed for an existing-system
install.

| Removed | Reason |
| --- | --- |
| `dwm-fedora.ks`, `dwm-fedora-nvidia.ks`, `dwm-fedora-image.ks` | Anaconda kickstarts |
| `branding/anaconda/` | Anaconda UI theming |
| `scripts/build-dwm-fedora-installer-iso.sh` | Fedora ISO authoring (`xorriso` + `implantisomd5`) |
| `scripts/build-dwm-fedora-system-image.py` | QEMU/libguestfs image factory |
| `scripts/image/` | factory-image `%post` scripts |
| `tests/containers/fedora-44/` | Fedora CI container |

### DNF-specific helpers

| Removed | Reason |
| --- | --- |
| `scripts/dwm-dnf-defaults`, `config/dnf/40-dwm-titus.conf` | installs `/usr/share/dnf5/libdnf.conf.d/…`; DNF5 does not exist on Debian and `apt` has no equivalent drop-in concept |
| `scripts/dwm-initial-update`, `scripts/dwm-initial-update-root` | first-boot mirror measurement built directly on `libdnf5`'s `RepoQuery`, metalink rewriting and `dnf5 upgrade`. Reimplementing that against apt is a separate project, not a port; its removal is a documented feature gap, not a silent one |
| `tests/test-dnf-defaults.py`, `tests/test-initial-update*.{sh,py}`, `tests/test-image-*.{sh,py}` | tests for the above |

### Other removals

| Removed | Reason |
| --- | --- |
| `scripts/nvidia-suspend-test.sh` | reads `/etc/mkinitcpio.conf` (Arch), `/etc/dracut.conf[.d]` (Fedora) and Fedora NVIDIA unit wiring. Not portable and not required |
| `scripts/run-tests-podman`, `tests/test-run-tests-podman.sh` | Fedora 44 container runner |
| `tests/test-update-center-terminal.py` | exercised the `dnf5` recovery executor. The executor is now `apt-get`; remaining coverage is the allowlist assertion in `tests/test-platform.sh` plus `tests/test-update-center.py`. **This is a real reduction in coverage** — see `tests/RESULTS.md` |
| `tests/test-kickstart-variants.sh`, `tests/test-fedora-*.sh` | replaced by `tests/test-platform.sh` and `tests/test-package-map.sh` |

### Kept, but re-gated

`install-herdr`, `install-gearlever`, `dwm-flatpak-setup`, `power-management.sh`
(report mode), `protonrestart`, `nvidia-gpu`, `nvidia-temp`, `active-audio` and
the rest of `scripts/` are distro-neutral and were kept unchanged apart from the
gates listed in §5.

---

## 8. Naming and layout

The upstream project name appears in 1458 places across 155 files. dwm-fox was
renamed throughout, **including runtime paths**, so the result is genuinely
independent of the reference tree:

- `~/.config/dwm-titus/` → `~/.config/dwm-fox/`
- `~/.local/share/dwm-titus/` → `~/.local/share/dwm-fox/`
- `${XDG_STATE_HOME}/dwm-fox/desktop-update`
- `/usr/local/libexec/dwm-fox/`
- `/usr/local/share/dwm-fox/`
- `/var/lib/dwm-fox/`
- `dwm.c`'s `dwmdir` string, `scripts/dwm-titus-release` → `scripts/dwm-fox-release`,
  `dwm-titus.png` → `dwm-fox.png`

Deliberately **kept** pointing at upstream, because they are provenance, not
identity:

- `https://github.com/ChrisTitusTech/dwm-titus.git` — the upstream source the
  desktop updater fetches from (`SOURCE` in `scripts/dwm-desktop-update`, and the
  `url=` in the Update Center's project link)
- documentation links under `dwm.christitus.com`
- `https://github.com/ChrisTitusTech/nord-background.git` — the wallpaper set

---

## 9. Deliberate functional differences

1. **`make install` requires root.** Upstream's `install-cursors` and
   `install-app-themes` sub-targets write under `${DESTDIR}${DATADIR}` without
   escalation, so `make install` fails as a normal user. `install.sh` always used
   `sudo make install`; the manual path is documented as `sudo make install` in
   `README.md`.
2. **Update provider identity** is `debian`, not `fedora` (§5). Any state written
   by a previous Fedora install is not readable, which is expected for a
   different platform.
3. **Gaming repositories** are gated on Ubuntu's `multiverse` component instead of
   the Gamescope COPR and RPM Fusion nonfree.
4. **Screen locking** is opt-in (§6).
5. **No ISO path.** dwm-fox is an existing-system installer only.
6. **The first-boot update center** (`dwm-initial-update`) is absent (§7).

---

## 10. Tests

| New / rewritten | Covers |
| --- | --- |
| `tests/test-platform.sh` | family mapping, installer gate in both directions, package-manager wiring, no live rpm/dnf invocation from a non-gated script |
| `tests/test-package-map.sh` | every profile resolves, no RPM-era names, every name resolvable via `apt-cache`, no duplicates, `install.sh` cannot drift from the aggregates, `light-locker` stays opt-in |
| `tests/test-qt-runtime-modules.sh` | QML imports ↔ `qt-runtime` package map, both directions |
| `tests/test-dwm-session.sh` | session launcher environment repair, single-pass D-Bus wrapper, missing-dwm reporting |
| `tests/test-session-setup.sh` | session integration is additive, idempotent and reversible (sandboxed root, real fixture account) |
| `tests/test-quickshell-repo.sh` | pinned fingerprint, deb822 shape, suite scoping, root ownership, `core` profile stays clear of the PPA |
| `tests/test-packagekit-floor.py` | Debian version split, floor ordering, malformed-input guards |
| `tests/test-dev-sync-install.sh` | updated for apt; the `sleep` stand-in replaced because coreutils multicall binaries reject unknown `argv[0]` |
| `tests/test-run-tests.sh` | retargeted from `check-fedora-platform` to `check-platform` |

Makefile targets: `check-platform`, `check-package-map`,
`check-quickshell-session-setup`. Run them with `make check-platform
check-package-map check-quickshell-session-setup`.

See `tests/RESULTS.md` for what passed and what did not.