# NOTICE

## This project

dwm-fox is a port of **dwm-titus** by Chris Titus Tech
(<https://github.com/ChrisTitusTech/dwm-titus>, MIT / X Consortium licensed) to
Debian and Ubuntu.

The window-manager sources (`dwm.c`, `drw.c`, `util.c`, `tomlparser.c` and their
headers), the Quickshell panel and its QML, the TOML hotkey/theme/window-rule
system, the theme and cursor assets, the session bootstrap, and the helper
scripts are the work of the dwm-titus authors and are redistributed here under
the same terms.

Changes made in this repository are documented exhaustively in
[`MIGRATION.md`](MIGRATION.md). In summary, they are:

- a Debian/Ubuntu platform gate and `apt` package map;
- `rpm`/`dnf` code paths replaced with `dpkg`/`apt` equivalents;
- a new session layer for headless Ubuntu Server (`scripts/dwm-session`,
  `scripts/dwm-session-setup.sh`);
- the Quickshell PPA provisioning layer;
- removal of the Fedora image, ISO and DNF-only machinery;
- a project-wide rename from `dwm-titus` to `dwm-fox`.

## Upstream projects and their licences

| Component | Upstream | Licence |
| --- | --- | --- |
| dwm | <https://dwm.suckless.org> by the dwm authors | MIT / X Consortium — see `LICENSE` |
| dwm-titus desktop | <https://github.com/ChrisTitusTech/dwm-titus> | MIT / X Consortium |
| Quickshell | <https://quickshell.org> | LGPL-3.0 |
| Capitaine Cursors | `assets/cursors/COPYING` | see that file |
| Nordic GTK theme | <https://github.com/EliverLara/Nordic> | MIT — cloned by `install.sh` |
| Meslo Nerd Font | <https://github.com/ryanoasis/nerd-fonts> | SIL Open Font License 1.1 |
| Nord backgrounds | <https://github.com/ChrisTitusTech/nord-background> | cloned by `install.sh` |

Quickshell is installed from a third-party repository and is **not** vendored in
this repository; it remains under its own LGPL-3.0 licence at
`/usr/share/licenses/quickshell` after installation.

The `Dwm-*` GTK palettes in `assets/themes/` are dwm-fox applications of the
shipped colour schemes and are covered by the same MIT / X Consortium licence as
the rest of this repository.

## Trademarks

All product names, logos and brands are property of their respective owners.
Their use here is for identification and does not imply endorsement.

## Security

Report security issues privately. See [`SECURITY.md`](SECURITY.md).