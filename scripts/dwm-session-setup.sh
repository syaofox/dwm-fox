#!/usr/bin/env bash
# dwm-session-setup.sh — Ubuntu/Debian session and platform integration.
#
# Ubuntu Server ships no desktop environment. Installing dwm-fox therefore needs
# more than package installation: the session must be reachable from a TTY, the
# user must be allowed to drive the graphics hardware, and the systemd user
# session that Quickshell, PipeWire and the polkit helpers depend on must exist
# outside a display-manager login.
#
# Everything this script changes is additive, idempotent, and reversible through
# the `uninstall` subcommand. Nothing here touches the bootloader, SSH, the
# firewall, AppArmor, SELinux, or the systemd default target.
#
# Usage: dwm-session-setup.sh {install|uninstall|status} [--user NAME] [--no-linger]

set -euo pipefail

PREFIX_DEFAULT="/usr/local"
XSESSION_FILE="/usr/share/xsessions/dwm.desktop"
XDG_AUTOSTART_FILE="/etc/xdg/autostart/dwm-fox-session.desktop"
STATE_DIR="/var/lib/dwm-fox"
BACKUP_DIR="${STATE_DIR}/session-setup-backup"
# Every system path this script touches is a variable so the test suite can
# redirect the whole tree at a sandbox root without root.
PAM_XSESSION_FILE="/etc/pam.d/xsession"

# Groups that grant access to the graphics and input devices. Ubuntu normally
# handles this through logind's dynamic ACLs, but those only apply to a seat
# session. Under startx there is no seat session, so explicit membership is
# required for Xorg to reach /dev/dri and libinput devices.
REQUIRED_GROUPS=(video render input audio)

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

TARGET_USER="$(id -un)"
ENABLE_LINGER=true

as_root() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		sudo "$@"
	else
		err "This action needs root privileges and sudo is unavailable."
		exit 1
	fi
}

ACTION=""
while (($# > 0)); do
	case "$1" in
	install | uninstall | status)
		ACTION=$1
		shift
		;;
	--user)
		(($# >= 2)) || {
			err "--user requires a value."
			exit 1
		}
		TARGET_USER=$2
		shift 2
		;;
	--no-linger)
		ENABLE_LINGER=false
		shift
		;;
	-h | --help)
		printf 'usage: %s {install|uninstall|status} [--user NAME] [--no-linger]\n' "${0##*/}"
		exit 0
		;;
	*)
		err "Unknown option: $1"
		printf 'usage: %s {install|uninstall|status} [--user NAME] [--no-linger]\n' "${0##*/}" >&2
		exit 1
		;;
	esac
done

[[ -n $ACTION ]] || {
	err "An action is required."
	printf 'usage: %s {install|uninstall|status} [--user NAME] [--no-linger]\n' "${0##*/}" >&2
	exit 2
}

id "$TARGET_USER" >/dev/null 2>&1 || {
	err "Unknown user: $TARGET_USER"
	exit 1
}

# ── state directory ───────────────────────────────────────
ensure_state_dir() {
	as_root install -d -o root -g root -m 0755 "$STATE_DIR"
	ok "State directory ready: $STATE_DIR"
}

# ── graphics / input / audio group membership ─────────────
configure_groups() {
	local group missing=0

	for group in "${REQUIRED_GROUPS[@]}"; do
		if ! getent group "$group" >/dev/null 2>&1; then
			warn "Group $group does not exist on this system; skipping."
			missing=1
			continue
		fi
		if id -nG "$TARGET_USER" | tr ' ' '\n' | command grep -Fxq "$group"; then
			continue
		fi
		info "Adding $TARGET_USER to the $group group..."
		as_root usermod -aG "$group" "$TARGET_USER"
	done

	if ((missing)); then
		warn "One or more hardware groups are absent. Input, audio and DRM access may be limited."
	else
		ok "Hardware group membership verified for $TARGET_USER."
	fi
	info "Group changes take effect at the next login."
}

# ── systemd user session ──────────────────────────────────
# startx does not create a logind session, so no systemd --user instance exists
# and wm-graphical-session.service cannot start. Enabling linger keeps the user's
# manager running, which makes `systemctl --user` usable from a bare TTY login.
configure_linger() {
	if ! command -v loginctl >/dev/null 2>&1; then
		warn "loginctl is unavailable; the systemd user session will not be prepared."
		return 1
	fi

	local state
	state=$(loginctl show-user "$TARGET_USER" -p Linger --value 2>/dev/null || printf 'unknown')
	case "$state" in
	yes)
		ok "Linger is already enabled for $TARGET_USER."
		return 0
		;;
	esac

	if [[ $ENABLE_LINGER != true ]]; then
		warn "Linger left disabled (--no-linger)."
		warn "Without it, startx sessions have no systemd user manager and"
		warn "xdg-desktop-autostart targets, PipeWire and polkit agents may not start."
		return 0
	fi

	info "Enabling systemd linger for $TARGET_USER..."
	if as_root loginctl enable-linger "$TARGET_USER"; then
		ok "Linger enabled. Revoke with: loginctl disable-linger $TARGET_USER"
	else
		warn "Could not enable linger for $TARGET_USER."
		warn "Prefer a display-manager login, or run: sudo loginctl enable-linger $TARGET_USER"
	fi
}

# ── XDG autostart activation ──────────────────────────────
# dwm's autostart.sh starts wm-graphical-session.service, which pulls in
# graphical-session.target and xdg-desktop-autostart.target. That is the only
# thing that makes /etc/xdg/autostart entries (polkit agent, keyring daemon,
# desktop portals) run. This desktop file is a second, independent activation
# point for display-manager sessions that do not run dwm's autostart script.
install_xdg_autostart() {
	local tmp
	tmp=$(mktemp)
	cat >"$tmp" <<-'UNIT'
		[Desktop Entry]
		Type=Application
		Name=dwm-fox graphical session
		Comment=Activate systemd graphical-session targets for the dwm-fox X11 session
		Exec=systemd-run --user --scope --quiet --collect -p Type=oneshot -p RemainAfterExit=yes /bin/true
		NoDisplay=true
		Terminal=false
		Hidden=false
		X-DW-FOX-SESSION=1
	UNIT
	as_root install -d -m 0755 "$(dirname "$XDG_AUTOSTART_FILE")"
	as_root install -o root -g root -m 0644 "$tmp" "$XDG_AUTOSTART_FILE"
	rm -f "$tmp"
	ok "Installed $XDG_AUTOSTART_FILE"
}

# ── PAM: give startx-style logins a systemd user session ──
# /etc/pam.d/xsession does not exist on Ubuntu Server, so a PAM-driven X login
# never gets pam_systemd and therefore never gets a systemd user session. Adding
# it makes future display-manager sessions consistent. It is additive: nothing
# existing is modified, and its removal is recorded so `uninstall` can undo it.

# Written into the generated file so a later run recognises its own output.
readonly DWM_PAM_MARKER='Installed by dwm-fox.'
readonly DWM_PAM_STACK='@include common-auth
@include common-account
@include common-session
@include common-password
@include common-auth'

configure_pam_xsession() {
	local pam_file="$PAM_XSESSION_FILE"

	if as_root test -e "$pam_file"; then
		# The stack this script writes must be recognised when it reads it back.
		# Testing only for a literal "pam_systemd.so" would miss the generated
		# file, whose comment names the module but whose directive is the
		# @include that actually provides it. Missing that would make a second
		# install back up the file it created and "restore" it on uninstall,
		# leaving it behind forever.
		if as_root grep -qF "$DWM_PAM_MARKER" "$pam_file"; then
			ok "$pam_file already provides a systemd user session (managed by dwm-fox)."
			return 0
		fi
		if as_root grep -qxF '@include common-session' "$pam_file"; then
			ok "$pam_file already provides a systemd user session."
			return 0
		fi
		info "Adding a systemd user session to $pam_file (backed up first)..."
		as_root install -d -m 0755 "$BACKUP_DIR"
		as_root cp -a "$pam_file" "$BACKUP_DIR/xsession.pam"
		printf '%s\n' "$DWM_PAM_MARKER" | as_root tee -a "$pam_file" >/dev/null
		printf '%s\n' "$DWM_PAM_STACK" | as_root tee -a "$pam_file" >/dev/null
		ok "Updated $pam_file"
		return 0
	fi

	as_root install -d -m 0755 "$(dirname "$pam_file")"
	local tmp
	tmp=$(mktemp)
	{
		printf '%s\n' '#%PAM-1.0' \
			"# $DWM_PAM_MARKER Provides a systemd user session (pam_systemd)" \
			'# so a PAM-driven X11 login gets graphical-session.target, PipeWire' \
			'# and polkit support, matching what LightDM and GDM already do.'
		printf '%s\n' "$DWM_PAM_STACK"
	} >"$tmp"
	as_root install -o root -g root -m 0644 "$tmp" "$pam_file"
	rm -f "$tmp"
	# The marker must be written with the same privilege path as the file it
	# describes, because BACKUP_DIR is root-owned in a real installation.
	as_root install -d -m 0755 "$BACKUP_DIR"
	printf '%s\n' created | as_root tee "$BACKUP_DIR/xsession.pam.created" >/dev/null
	ok "Created $pam_file"
}

# ── keyring and PAM keyring integration ───────────────────
configure_keyring_pam() {
	if ! command -v update pam-auth-update >/dev/null 2>&1; then
		return 0
	fi
	# gnome-keyring on Ubuntu ships the pam module; registering it makes the
	# login keyring unlock with the password.
	if as_root test -f /usr/lib/x86_64-linux-gnu/security/pam_gnome_keyring.so ||
		as_root test -f /usr/lib/security/pam_gnome_keyring.so; then
		info "Registering the gnome-keyring PAM module..."
		if as_root pam-auth-update --package --priority=50 --package gnome-keyring >/dev/null 2>&1; then
			ok "gnome-keyring PAM integration registered."
		else
			warn "Could not register gnome-keyring with pam-auth-update."
		fi
	else
		ok "gnome-keyring is not installed; skipping PAM keyring registration."
	fi
}

# ── verification ──────────────────────────────────────────
verify_xsession_entry() {
	if as_root test -f "$XSESSION_FILE"; then
		ok "X session entry present: $XSESSION_FILE"
	else
		warn "X session entry missing: $XSESSION_FILE (run make install-system)"
	fi
}

verify_session_launcher() {
	local launcher="$PREFIX_DEFAULT/bin/dwm-session"
	if as_root test -x "$launcher"; then
		ok "Session launcher installed: $launcher"
	else
		warn "Session launcher missing: $launcher (run make install-system)"
	fi
}

install_session() {
	info "Configuring the Ubuntu session integration for $TARGET_USER..."
	ensure_state_dir
	configure_groups
	configure_linger
	install_xdg_autostart
	configure_pam_xsession
	configure_keyring_pam
	verify_session_launcher
	verify_xsession_entry
	ok "Session integration complete."
}

uninstall_session() {
	info "Reverting the Ubuntu session integration..."

	if as_root test -f "$XDG_AUTOSTART_FILE"; then
		as_root rm -f "$XDG_AUTOSTART_FILE"
		ok "Removed $XDG_AUTOSTART_FILE"
	fi

	if as_root test -f "$BACKUP_DIR/xsession.pam"; then
		as_root cp -a "$BACKUP_DIR/xsession.pam" "$PAM_XSESSION_FILE"
		as_root rm -f "$BACKUP_DIR/xsession.pam"
		ok "Restored /etc/pam.d/xsession from backup"
	elif as_root test -f "$BACKUP_DIR/xsession.pam.created"; then
		as_root rm -f "$PAM_XSESSION_FILE"
		as_root rm -f "$BACKUP_DIR/xsession.pam.created"
		ok "Removed the created /etc/pam.d/xsession"
	else
		ok "/etc/pam.d/xsession was left unchanged"
	fi

	if command -v loginctl >/dev/null 2>&1 &&
		[[ $(loginctl show-user "$TARGET_USER" -p Linger --value 2>/dev/null || echo no) == yes ]]; then
		info "Disabling systemd linger for $TARGET_USER..."
		as_root loginctl disable-linger "$TARGET_USER" || warn "Could not disable linger."
	fi

	info "Group membership (video, render, input, audio) was left in place."
	info "Remove manually with: sudo gpasswd -d $TARGET_USER <group>"
	ok "Session integration reverted."
}

status_session() {
	printf 'user:            %s\n' "$TARGET_USER"
	printf 'state dir:       %s\n' "$STATE_DIR"
	printf 'xsession entry:  %s\n' \
		"$(as_root test -f "$XSESSION_FILE" && echo present || echo absent)"
	printf 'xdg autostart:   %s\n' \
		"$(as_root test -f "$XDG_AUTOSTART_FILE" && echo present || echo absent)"
	printf 'pam xsession:    %s\n' \
		"$(as_root test -f "$PAM_XSESSION_FILE" && echo present || echo absent)"
	printf 'linger:          %s\n' \
		"$(loginctl show-user "$TARGET_USER" -p Linger --value 2>/dev/null || echo unknown)"
	printf 'groups:          %s\n' "$(id -nG "$TARGET_USER")"
	printf 'xinit:           %s\n' "$(command -v startx 2>/dev/null || echo absent)"
	printf 'x server:        %s\n' "$(command -v Xorg 2>/dev/null || echo absent)"
	printf 'quickshell:      %s\n' \
		"$(command -v quickshell >/dev/null 2>&1 && quickshell --version 2>/dev/null | head -1 || echo absent)"
	printf 'session bus:     %s\n' "${DBUS_SESSION_BUS_ADDRESS:-unset}"
	printf 'xdg runtime dir: %s\n' "${XDG_RUNTIME_DIR:-unset}"
}

case "$ACTION" in
install) install_session ;;
uninstall) uninstall_session ;;
status) status_session ;;
esac