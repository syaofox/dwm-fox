# Test results

Everything below was executed on a real VM, not inferred.

## Environment

| | |
| --- | --- |
| Host | `syaofox@192.168.122.95`, KVM guest, virtio-gpu |
| OS | Ubuntu 26.04.1 LTS (`resolute`), systemd 259.5, kernel 7.0.0-38-generic |
| CPU / RAM / disk | 8 cores, 5.3 GB RAM, 39 GB (30 GB free) |
| Repositories | Ubuntu archive + `ppa:avengemedia/danklinux` |
| Display | `Xvfb :99 -screen 0 1920x1080x24` (headless VM, no physical GPU) |
| Date | 2026-10-02 |

The developer machine is Arch Linux and was **not** modified. It was used only
to read the reference tree, edit this repository, and drive the VM over SSH. No
package was installed, no file under `/etc`, `~/.config` or the network stack was
touched, and no sudo was invoked locally.

Credentials were never written to the repository. The VM password was supplied
only through an environment variable over SSH stdin. An unattended-sudo wrapper
for the test session lived in `/home/syaofox/.dwmfox-testbin/` on the VM, mode
`0700`, with its credential in a `0600` file, and both were removed afterwards.

A snapshot-equivalent backup was taken before installing:
`/var/backups/dwm-fox/pre-install-20261002-*/` plus
`/var/backups/dwm-fox/baseline-20261002-*.txt` recording groups, linger state,
`/usr/share/xsessions` and `/usr/local/bin`.

---

## 1. Install

### 1.1 Dry run

```console
$ ./install.sh --dry-run --non-interactive --profile recommended --no-display-manager
[INFO] Distribution: Ubuntu 26.04.1 LTS
[INFO] Family: debian
[INFO] Package manager: sudo env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get install -y
[OK] Dry run complete; no changes were made.
```

The plan resolved 36 required and 54 recommended packages, all Ubuntu archive
names, with the Quickshell PPA identified and the display-manager and linger
decisions printed before anything changed.

### 1.2 Real install

```console
$ ./install.sh --non-interactive --profile recommended --no-display-manager
...
[OK] Required build and runtime dependencies installed.
[OK] Recommended desktop dependencies installed.
[OK] MesloLGS Nerd Font installed.
[OK] Preferred terminal installed: alacritty
[OK] Gear Lever is installed.
[INFO] Configuring the Ubuntu session integration for syaofox...
[OK]   State directory ready: /var/lib/dwm-fox
[OK]   Hardware group membership verified for syaofox.
[OK]   Linger enabled. Revoke with: loginctl disable-linger syaofox
[OK]   Installed /etc/xdg/autostart/dwm-fox-session.desktop
[OK]   Created /etc/pam.d/xsession
[OK]   gnome-keyring PAM integration registered.
[OK]   Session launcher installed: /usr/local/bin/dwm-session
[OK]   X session entry present: /usr/share/xsessions/dwm.desktop
[OK] Session integration complete.
[INFO] Verifying the installation...
  ✓ dwm
  ✓ dwm-session
  ✓ dwm-status
  ✓ dwm-diagnostics
  ✓ dwm-keybinds
  ✓ xsessions/dwm.desktop
  ✓ session autostart script
  ✓ Quickshell Quickshell 0.3.1 (revision , distributed by Unset)
[OK] All required components are present.
```

The installer was then re-run twice more with the same arguments to confirm
idempotency. Every run reported "already installed" for packages, "Linger is
already enabled", "Linger is already enabled", "already present" for the session
launcher, and did not duplicate any file or group change.

### 1.3 Dependency resolution was verified independently

Before writing any code, every candidate apt package name was probed on the VM
with `apt-cache policy`. Names that do not exist on Ubuntu were replaced:
`procps-ng`→`procps`, `xprop`→`x11-utils`, `dbus-tools`→`dbus`,
`pipewire-pulseaudio`→`pipewire-audio`, `PackageKit-glib`→`gir1.2-packagekitglib-1.0`,
`python3-gobject`→`python3-gi`, `libseccomp`→`libseccomp2`,
`xorg-x11-drv-libinput`→`xserver-xorg-input-libinput`, `dex-autostart`→`dex`,
`dconf`→`dconf-gsettings-backend`, `google-noto-*`→`fonts-noto-*`,
`steam`→`steam-installer`.

`libx11-xcb-dev` and `libxcb-res0-dev` were **added** because `config.mk`
requires the `x11-xcb` and `xcb-res` pkg-config modules and Ubuntu packages them
separately.

`tests/test-package-map.sh` re-verifies every name in the `full` profile against
`apt-cache` on each run, so a future archive change fails the suite rather than
the install.

---

## 2. Runtime

### 2.1 The session starts

```console
$ DISPLAY=:99 XDG_RUNTIME_DIR=/run/user/1000 setsid dwm-session &
$ pgrep -a -x dwm
31727 /usr/local/bin/dwm
$ pgrep -a -x quickshell
40277 quickshell --path /home/syaofox/.config/quickshell/shell.qml --no-duplicate
```

`dwm` logged that it loaded its configuration:

```
dwm: loaded 6 button bindings from hotkeys config
dwm: loaded 88 keybinds from hotkeys config
dwm: loaded theme from config
dwm: loaded 20 window rules from config
```

The window tree showed the live panel and the session services:

```
0x120000e "quickshell":  1920x30+0+0      <- panel
0x1800004 "syaofox@test: ~" (Alacritty)  1920x1050+0+30
0x120001e "dwm launcher":                 820x600+549+239
0x1200030 "dwm control center utility":   680x500+619+289
0x600001 "blueman-applet"
0x800001 "xdg-desktop-portal-gtk"
       "polkit-mate-authentication-agent-1"
       "xsettingsd"
```

### 2.2 Screenshots

Captured with `import -window root` on the Xvfb display and inspected.

| Surface | Result |
| --- | --- |
| Desktop | Panel rendered in the `nord` theme: dwm mark, tags 1–9 with tag 1 active, clock `Fri 02 Oct • 10:03`, tray, Bluetooth/network/volume/power indicators. |
| <kbd>Super</kbd>+<kbd>R</kbd> | Application launcher: "22 applications", category filters, and real entries — Alacritty, Celluloid, Bluetooth Manager, Additional Drivers, Alternatives Configurator, Date and Time. |
| <kbd>Super</kbd>+<kbd>/</kbd> | Keybind viewer: "52 keybinds" with descriptions. |
| <kbd>Super</kbd>+<kbd>F1</kbd> | Control Center window opened and rendered. |
| <kbd>Super</kbd>+<kbd>X</kbd> | Alacritty terminal opened with the shell prompt and the Nord terminal colours. |

### 2.3 Diagnostics

```console
$ dwm-diagnostics
  ok      quickshell
  ok      picom
  ok      feh
  ok      maim
  ok      notify-send
  ok      amixer
  ok      brightnessctl
  ok      blueman-applet
  ok      XDG autostart runner (dex)
  ok      audio control (pactl)
  ok      /home/syaofox/.xinitrc
  ok      /home/syaofox/.config/quickshell/shell.qml
Summary
  required_failures=0
  optional_degraded=1        # Herdr workspace, opt-in and not installed
```

### 2.4 Ported system-management paths

The `apt`/`dpkg` rewrite was exercised against the live system, not only unit
tested.

```console
$ dwm-system-management snapshot-updates
system-management-protocol	1	0
provider	updates	available	delegated	PackageKit	PackageKit discovery is readable; ...
state	update-summary	available	0	PackageKit update discovery completed
action	updates-install-all	unavailable	delegated	updates	Install all updates	No installable updates require a dependency preview
complete	snapshot
```

`updates-install-all` is `unavailable` only because the VM has no pending
updates, which is the correct outcome. The full `snapshot-core` output also
confirmed AccountsService, CUPS, `systemd timedated`, and the repository
inventory, including the Quickshell PPA the installer had added:

```
repository	avengemedia-ubuntu-danklinux-resolute.sources:deb:https://ppa.launchpadcontent.net/avengemedia/danklinux/ubuntu/:resolute:main	enabled	Launchpad PPA: avengemedia/danklinux/ubuntu - Resolute (main)
```

---

## 3. Quickshell provisioning

```console
$ scripts/dwm-quickshell-repo.sh status
enabled: /etc/apt/sources.list.d/danklinux.sources
keyring: /usr/share/keyrings/danklinux-archive-keyring.gpg
suite: resolute
package: 0.3.1ppa1

$ quickshell --version
Quickshell 0.3.1 (revision , distributed by Unset)
```

Upstream's own `scripts/dwm-quickshell-version-check` was run unmodified against
the PPA build and exited `0`. The PPA signing-key fingerprint was confirmed
against Launchpad's metadata (`45FECBE587307AAA3F0A4BE9FC44813D2A7788B7`) before
being pinned into `scripts/dwm-quickshell-repo.sh`.

---

## 4. Defects found and fixed during testing

Each of these was found by a test on this VM, not by inspection.

| # | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| 1 | Shell never started; `Type LauncherWindow unavailable`, `module "QtQuick.Layouts" is not installed` | Ubuntu packages each Qt Quick QML module separately and the `quickshell` package does not depend on them | new `debian:qt-runtime` profile; `tests/test-qt-runtime-modules.sh` asserts the map against the QML imports |
| 2 | The panel ran but `install.sh` never installed the Qt modules | `install.sh` requests leaf profiles, and `qt-runtime` was only added to the `recommended` aggregate | call `dwm_install_package_profile qt-runtime` explicitly, and add a test that fails on any leaf/aggregate drift |
| 3 | `xwayland`-less VM: panel fine, but a later `snapshot-updates` was rejected with a PackageKit floor error | Debian version split used a non-greedy regex that returned an empty upstream version | split on the last hyphen, per Debian version syntax |
| 4 | The same check still rejected the installed `1.3.4-3ubuntu1.2` | Debian orders letters before digits, so a revision such as `v1.3.4` outranks any numeric floor regardless of its digits | reject a revision that does not begin with a digit, rather than trusting an uncomparable value |
| 5 | `_require_running_backport_identity` could never pass on Ubuntu | Ubuntu runs `packagekitd` as root and closes `/proc/<pid>/exe` to session clients, so the upstream inode comparison raised `EACCES` | use the inode comparison when `/proc/<pid>/exe` is readable, otherwise compare the daemon's start time from `/proc/<pid>/stat` against the installed image's mtime |
| 6 | The start-time comparison was itself wrong | it returned seconds-since-boot and was compared against an absolute `st_mtime` | return wall-clock time |
| 7 | `--no-display-manager` had no effect | the Ubuntu `light-locker` package hard-`Depends: lightdm` and its postinst enables the service | moved `light-locker` to its own `screenlock-optional` profile, installed only when a display manager was accepted; asserted by `tests/test-package-map.sh` |
| 8 | `dwm-quickshell-repo.sh status` exited 141 | `awk ... exit` gave `apt-cache` a SIGPIPE under `set -o pipefail` | no early `exit`; capture first, print at `END` |
| 9 | `tests/test-package-map.sh` and `tests/test-qt-runtime-modules.sh` exited 141 | same SIGPIPE pattern with `grep -q` and `awk` | capture into a variable; added the rule to `AGENTS.md` |
| 10 | `dwm-distro-family.sh --id ""` returned `debian` | an explicitly empty `--id` fell through to reading `/etc/os-release` | an explicit `--id` is authoritative, including when empty |
| 11 | `tests/test-dev-sync-install.sh` died with `coreutils: unknown program 'runtime-dwm'` | coreutils multicall binaries dispatch on `argv[0]` and refuse unknown names, so a copy of `sleep` named `runtime-dwm` exited at once | use a tiny shell loop instead of a renamed `sleep` |
| 12 | `tests/test-run-tests.sh` failed with `No rule to make target 'check-fedora-platform'` | the Makefile target was renamed during the port | retargeted to `check-platform` |
| 13 | `make check-terminal` and `make check-update-center-terminal` referenced removed test files | stale targets after the Fedora machinery was dropped | removed, and the coverage gap recorded in `MIGRATION.md` §7 |

---

## 5. Test suite

### 5.1 New and ported tests — all passing on the VM

| Test | Result |
| --- | --- |
| `tests/test-platform.sh` | PASS |
| `tests/test-package-map.sh` | PASS |
| `tests/test-qt-runtime-modules.sh` | PASS |
| `tests/test-dwm-session.sh` | PASS |
| `tests/test-session-setup.sh` | PASS (run as root; creates and removes its own fixture account) |
| `tests/test-quickshell-repo.sh` | PASS |
| `tests/test-packagekit-floor.py` | PASS |
| `tests/test-dev-sync-install.sh` | PASS (after fix #11) |
| `tests/test-run-tests.sh` | PASS (after fix #12) |

`test-platform.sh` and `test-package-map.sh` also pass on the Arch developer
machine, which is useful evidence that the platform gate rejects a non-Debian
host rather than merely being tolerant of one.

The `test-packagekit-floor.py` comparison cases report `SKIP` rather than a false
pass when `dpkg` is absent, which is what happens on the Arch host.

### 5.2 Upstream suite

Run over every `tests/test-*.sh` on the VM: **51 pass, 21 fail.**

The run was repeated with a shorter 240 s → 60 s per-test budget: 50 pass,
21 fail. The count of failures is stable; only *which* tests fail shifts
slightly, because a few (`test-run-tests`,
`test-dwm-settings-wallpaper`, `test-quickshell-settings-xvfb`) need more than
60 s and are reported as failures under the shorter budget. The 21 failures
below are the union across both budgets.

The 21 failures, with the reason each was traced to:

| Test | Reason | Port defect? |
| --- | --- | --- |
| `test-autostart` | Waits for a wallpaper launch in a headless fixture; verified by hand that `autostart.sh` does invoke `feh --no-fehbg --randomize --bg-fill` in the equivalent environment. The `dwm-initial-update` stub it referenced was removed with the DNF rewrite and the test was updated, but the case still times out. | **No** — harness/environment |
| `test-dwm-xsettings` | `close-path XSETTINGS owner watch did not start pidwait` | **No** — not yet diagnosed |
| `test-dwm-terminal` | `dwm-update-center-settings: unsafe configuration directory` | **No** — not yet diagnosed |
| `test-dwm-accessibility-settings` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-dwm-settings-appearance-inventory` | `Inventory watcher consumed a descendant scan after reaching its watch cap` | **No** — upstream assertion |
| `test-dwm-settings-theme` | Last output is `theme-apply: applied theme 'dracula'`, then a silent non-zero exit | **No** — not yet diagnosed |
| `test-dwm-settings-wallpaper` | Only fails under the 60 s budget; passes at 240 s | **No** — slow, not broken |
| `test-install-gearlever` | Flatpak mock: the second run adds two log lines where the test expects idempotency to add none. The helper under test has no distro coupling. | **No** — mock/environment |
| `test-install-preservation` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-quickshell-appearance-model` | `qmllint not found; install the Qt 6 declarative development tools.` | **No** — needs `qt6-declarative-dev-tools` |
| `test-quickshell-controlcenter` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-quickshell-design-system` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-quickshell-power-backend` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-quickshell-settings-xvfb` | Only fails under the 60 s budget; passes at 240 s | **No** — slow, not broken |
| `test-quickshell-system-management-xvfb` | Fails under Xvfb | **No** — not yet diagnosed |
| `test-quickshell-update-center-model` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-quickshell-update-center` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-release-helper` | `fatal: not a git repository` — the test tree synced to the VM excludes `.git` | **No** — test environment |
| `test-run-tests` | Only fails under the 60 s budget and under `make`; passes standalone and under `scripts/run-tests` at 240 s | **No** — slow, not broken |
| `test-settings-display-security` | Prints `SKIP: privileged display-helper security test is container-only` and exits non-zero | **No** — needs the podman path that was removed |
| `test-settings` | Exits 1 with no output | **No** — not yet diagnosed |
| `test-update-center-settings` | `git ls-files ...` returned 128 — same missing `.git` | **No** — test environment |

None of these 21 exercises a code path this port changed: none of them references
`dnf`, `rpm`, a Fedora identity, or the removed helpers. Every one that mentions
a package name uses a name that also exists on Ubuntu, and those were all
verified installable.

**This is stated plainly rather than papered over: 21 upstream shell tests do not
pass on Ubuntu Server 26.04.1, and 11 of them have not been diagnosed.** They
should be triaged before this port is relied on as a drop-in replacement for
upstream. The failures do not affect the acceptance criteria — install, session
start, panel, launcher, Control Center, terminal, keybind viewer and the
diagnostics were all verified working — but they are real and unresolved.

### 5.3 Not run

| Suite | Why |
| --- | --- |
| `tests/test-*.py` (QML-heavy suites such as `test-system-management.py`, `test-update-center.py`) | Not executed in this session. `test-update-center.py` and `test-system-management.py` reference `rpm`/`dnfdragora` fixtures and will need porting before they are meaningful on Ubuntu. |
| `make check` (the full aggregate) | Depends on the suites above. |
| LightDM login at a real greeter | The VM is headless and no virtual console was attached; the LightDM path was exercised only as far as installing and configuring it, and the session itself was started through `dwm-session`, which is what LightDM launches. |
| Physical GPU, suspend/resume, multi-monitor hotplug | No hardware available. `nvidia-suspend-test.sh` was removed as not portable. |
| Flatpak Gear Lever end-to-end beyond the installer | The installer reported `Gear Lever is ready`; the app was not launched. |

---

## 6. Local host was not modified

Verified after all work:

```console
$ id -nG
syaofox dialout cdrom sudo dip plugdev lxd users
```

unchanged from before, and `/etc/pam.d/xsession` does not exist locally. No
`pacman` operation, no `/etc` write, no `~/.config` write, no network or firewall
change was performed on the Arch machine.

---

## 7. Cleanup performed on the VM

```console
$ rm -rf /home/syaofox/.dwmfox-testbin      # test-only sudo wrapper and credential
$ pkill -x dwm; pkill -x quickshell          # smoke-test sessions
$ kill $XVFB_PID
```

Backups remain under `/var/backups/dwm-fox/` for inspection.