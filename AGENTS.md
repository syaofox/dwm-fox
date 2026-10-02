# AGENTS.md

## Purpose

This repository is a Debian/Ubuntu X11 desktop environment built around a
heavily patched fork of suckless dwm and a managed Quickshell shell. It is a
port of dwm-titus from Fedora. The product is an existing-system installer that
takes Ubuntu Server from no desktop to a usable dwm session.

Debian and Ubuntu are the sole supported distributions. Upstream dwm-titus is
Fedora-only, and this port keeps that discipline: an unknown OS identity must
fail clearly instead of entering an untested path.

Read `MIGRATION.md` before changing anything platform-dependent. It is the
authoritative record of what differs from upstream and why.

## Priorities

1. Preserve dwm stability and existing user workflows.
2. Keep the C window-manager core small, understandable and dependency-light.
3. Do not move desktop policy into the C event loop.
4. Preserve the install, session and rollback contract.
5. Keep installation and settings changes safe, repeatable, reversible and
   explicit.
6. Prefer focused changes that can be reviewed and tested independently.

## Support contract

The sole supported platform is Debian and Ubuntu, with Ubuntu Server 26.04.1 LTS
the tested baseline. Fedora branches in `scripts/dwm-utils.sh` and
`scripts/dwm-packages.sh` are retained for reference and diffability only;
`install.sh` rejects Fedora and says why. Any other OS identity must be refused
before package installation or system changes.

## Repository map

- `dwm.c`, `drw.c`, `util.c`, `tomlparser.c`: window-manager sources.
- `config.def.h`: version-controlled default compile-time configuration.
- `config.h`: local build configuration. Never overwrite user changes.
- `config.mk`: compiler, include, library and installation settings.
- `Makefile`: build, install, uninstall and test targets.
- `config/`: application configuration, default TOML runtime settings, and the
  managed Quickshell QML under `config/quickshell/`.
- `scripts/`: session startup, dependency checks, desktop helpers, operational
  scripts.
- `assets/`: bundled `Dwm-*` GTK palettes and Capitaine cursor themes.
- `lightdm/`: optional greeter configuration.
- `install.sh`: the supported existing-system installer.
- `uninstall` is provided by `sudo make uninstall` plus
  `scripts/dwm-session-setup.sh uninstall`.
- `AGENTS.md`: durable engineering and agent-execution rules.
- `MIGRATION.md`: itemised differences from upstream dwm-titus.
- `tests/RESULTS.md`: what was verified on a real VM, including failures.
- `README.md`: user documentation.
- `NOTICE.md`: attribution and licensing.

## Platform rules

- Detect the distribution through `/etc/os-release` and map it to a dependency-map
  family in exactly one place: `scripts/dwm-distro-family.sh`. The Makefile, the
  installer, the diagnostics and the tests must not disagree.
- Keep package-name lists in `scripts/dwm-packages.sh` only. Do not scatter them.
- `install.sh` requests leaf profiles (`desktop`, `qt-runtime`, …), not the
  aggregates. `tests/test-package-map.sh` fails if a profile exists in an
  aggregate but is never installed, because that drift is silent.
- Prefer `apt` over hand-built debs and avoid third-party repositories. The
  Quickshell PPA is the single exception and is documented in `MIGRATION.md` §4.
- Any third-party repository must pin and verify a signing-key fingerprint before
  the key is trusted, install root-owned, and be removable.
- Use `pkg-config` for library discovery. Do not add hardcoded library paths.
- Respect `CC`, `CFLAGS`, `CPPFLAGS`, `LDFLAGS`, `PREFIX`, `DESTDIR`,
  `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and the invoking user's
  home directory.
- Xorg is required. Wayland-native support is out of scope.
- Keep optional components optional. A missing Picom, wallpaper or terminal must
  not crash dwm.

## Ubuntu Server session rules

Ubuntu Server has no desktop, so the session layer is this port's own work and
needs explicit care.

- `scripts/dwm-session` is the single dwm entry point for both `startx` and a
  display manager. `dwm.desktop` must launch it, never dwm directly.
- Repair the session environment only when it is missing, in a fixed order:
  `XDG_RUNTIME_DIR`, then `XDG_DATA_HOME`/`XDG_CONFIG_HOME`, then the session
  D-Bus.
- The `dbus-run-session` re-exec must stay guarded by `DWM_FOX_DBUS_WRAPPED`; an
  unguarded re-exec loops forever.
- `scripts/dwm-session-setup.sh` must remain additive, idempotent and
  reversible, and must not touch the bootloader, SSH, the firewall, AppArmor,
  SELinux or the systemd default target.
- Back up a pre-existing file before modifying it, and restore it on uninstall.
- Never enable a display manager implicitly. `light-locker` hard-depends on
  LightDM on Ubuntu and its postinst enables the service, so it must stay opt-in.
- Under `startx` there is no logind seat session: device ACLs are not applied and
  there is no `systemd --user`. Both are handled explicitly (hardware groups,
  linger) and both must be documented and reversible.

## Configuration and compatibility

- Preserve `config.def.h` as the default template.
- Never replace an existing `config.h`, user TOML file, `.xinitrc` or application
  configuration without explicit consent or a backup.
- Runtime TOML files live under `${XDG_CONFIG_HOME:-$HOME/.config}/dwm-fox/`.
- Preserve hot reload for `hotkeys.toml`, `themes.toml` and `window-rules.toml`.
- `${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/` is managed exclusively by
  dwm-fox and may be replaced wholesale from tracked `config/quickshell/`.
- Relaunch the managed shell through
  `dwm-quickshell-controlcenter action restart-quickshell`. Do not start it with
  a repo-local `--path`: hotkeys target the managed config path, and Quickshell
  treats different paths as different IPC instances.
- Keep the Ubuntu package names for the Qt Quick QML modules in
  `dwm-packages.sh:qt-runtime` in sync with the imports in `config/quickshell`.
  `tests/test-qt-runtime-modules.sh` enforces this in both directions. The
  `quickshell` package does not depend on them, and omitting them makes the whole
  shell fail to load while `quickshell --version` still looks healthy.
- Keep existing keybindings, window rules, EWMH behavior, multi-monitor behavior
  and autostart behavior unless the task explicitly changes them.
- When changing defaults, update the documentation and `MIGRATION.md` in the
  same change.

## Shell and installer standards

- Use Bash only when Bash features are needed; otherwise POSIX `sh`.
- Bash scripts use `set -euo pipefail`; POSIX scripts use `set -eu`.
- Quote expansions, use `command -v`, and prefer a stable machine interface over
  parsing human-oriented output.
- Under `set -o pipefail`, never let a pipeline consumer exit early: `grep -q` or
  an `awk ... exit` hands the producer a SIGPIPE and the failure is reported
  against the wrong command. Capture into a variable first.
- Privilege escalation is limited to package installation and system-wide file
  installation. Never run the installer as root.
- Installation must be idempotent.
- Package installation and service enablement must be visible to the user. Never
  silently alter the bootloader, display manager, firewall, AppArmor, SELinux or
  the systemd default target.
- Network downloads must be optional, clearly reported and failure-tolerant
  unless the artifact is explicitly required.
- Run ShellCheck and shfmt on changed shell scripts when available.

## Build and code standards

- Keep the existing C99 style and compile with warnings enabled.
- Check allocation, file, Xlib/XCB, parser and process-launch failures.
- Do not introduce blocking work into the X event loop.
- Do not commit generated objects, binaries or local configuration.

## Required validation

Fastest useful loop:

```sh
make check-platform
make check-package-map
make check-quickshell-session-setup
```

Then the upstream suite through the managed workspace:

```sh
scripts/run-tests make clean all
scripts/run-tests
```

`tests/test-session-setup.sh` needs root because it creates a real throwaway
account and removes it on exit. Run it with `sudo`.

For shell changes:

```sh
shellcheck install.sh scripts/*.sh scripts/dwm-session scripts/dwm-distro-family.sh tests/*.sh
shfmt -d install.sh scripts/*.sh tests/*.sh
```

For installer or packaging changes, validate on a real VM:

```sh
./install.sh --dry-run --non-interactive --profile recommended
./install.sh --non-interactive --profile recommended --no-display-manager
```

A headless or virtual machine is enough. Start `Xvfb`, then run the installed
session launcher and confirm that dwm and quickshell are both alive:

```sh
Xvfb :99 -screen 0 1920x1080x24 +extension GLX +extension RANDR &  DISPLAY=:99 dwm-session &
pgrep -a -x dwm; pgrep -a -x quickshell
```

Record what was run, what passed and what did not in `tests/RESULTS.md`. Do not
claim coverage that was not executed.

Use `${DWM_TEST_TMP_ROOT:-$HOME/tmp}` for test workspaces and clear the exact run
directory afterwards. If a path could not be tested, state exactly what was not
tested.

## Change discipline

- Inspect `git status` before editing and preserve unrelated changes.
- Keep commits and patches narrowly scoped.
- Update `MIGRATION.md` only when platform differences intentionally change, and
  `README.md` when commands, dependencies or defaults change.
- Never stage or publish credentials, tokens, private keys or secret files.