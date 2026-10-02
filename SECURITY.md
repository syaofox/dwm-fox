# Security Policy

## Supported versions

dwm-fox targets the current Ubuntu LTS and current Debian stable. Fixes are
applied to the `main` branch and released from there.

## Reporting a vulnerability

Please report security issues privately rather than in a public issue. Include:

- what you did
- what you expected
- what happened
- the affected version and distribution

Do not include credentials, private keys, or personal data in a report. If you
accidentally include a secret, treat it as compromised and rotate it.

## Security-relevant design decisions

These are deliberate and should be preserved unless a change is made with a
specific replacement in mind.

### Privilege separation

- `install.sh` runs as a normal user and escalates only for package installation
  and system-wide file placement. It must never be run as root.
- Privileged helpers live in `${PREFIX}/libexec/dwm-fox/`, root-owned and
  non-writable, and are reached only through `pkexec` or `sudo`.
- Helpers validate every argument, allowlist every operation, and verify they
  are the installed copy before acting. A repository-local or user-writable copy
  must never be elevated.
- `dwm-update-center-terminal` resolves its privileged command through
  `trusted_native_command`, which allowlists `/usr/bin/apt-get` and
  `/usr/bin/sudo` and validates every directory and symlink hop. No other
  executable is reachable.

### Third-party repositories

The Quickshell PPA is the only third-party source. It is handled defensively:

- the signing key is downloaded over HTTPS from `keyserver.ubuntu.com`;
- its fingerprint is compared against a value pinned in
  `scripts/dwm-quickshell-repo.sh` **before** the key is dearmored, written or
  trusted;
- the key is installed root-owned to a dedicated keyring under
  `/usr/share/keyrings`, and the source pins it via `Signed-By:`;
- the source is a deb822 stanza scoped to the running release suite;
- `disable` removes only the files `enable` created.

### Package transaction safety

- apt runs non-interactively with `--force-confdef` and `--force-confold`, so a
  conffile prompt can neither hang an unattended install nor silently discard a
  local change.
- Package names are validated against Debian archive character rules before
  reaching `apt-get`, and `.rpm` names are rejected outright.
- Package updates driven from the UI require PackageKit to meet a documented
  Debian version floor, and require the running daemon to match the installed
  package. A version floor cannot be satisfied by a Debian revision that does not
  begin with a digit, because Debian orders letters before digits and such a
  revision could not be compared at all.
- The session-checkout verification in `dwm-desktop-update` and its privileged
  counterpart re-validate the identity and ownership of every path before
  replacing it, and are rollback-capable.

### Session integration

`scripts/dwm-session-setup.sh` is additive and reversible. It does not modify the
bootloader, SSH, the firewall, AppArmor, SELinux, or the systemd default target.
It backs up a pre-existing `/etc/pam.d/xsession` before touching it and restores
it on `uninstall`.

### Display-manager policy

Installing a display manager changes what starts at the next boot. dwm-fox never
enables one implicitly: `startx` needs none, `--no-display-manager` prevents it,
and the default prompts only on an interactive run. `light-locker` is opt-in for
exactly this reason — on Ubuntu it hard-depends on LightDM and its postinst
enables the service.

### Credentials

No credential is stored in this repository. The installer reads the sudo
password interactively. Test harnesses that need unattended sudo read it from
the environment and keep it outside the tree.