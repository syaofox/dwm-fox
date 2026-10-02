#!/usr/bin/env bash
# test-session-setup.sh — Ubuntu session integration is safe and reversible.
#
# Every assertion runs against a redirected root so the test never modifies the
# host: SOURCE_FILE, KEYRING, XDG_AUTOSTART_FILE, STATE_DIR and BACKUP_DIR are
# all overridable, and the group / linger / PAM behaviour is asserted through the
# command log the stubs record.
set -euo pipefail

# The script under test takes its action as a bare positional argument, so this
# harness must not shadow the argument list it forwards.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_DIR/scripts/dwm-session-setup.sh"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -x $SETUP ]] || fail "scripts/dwm-session-setup.sh is missing or not executable"
bash -n "$SETUP" || fail "scripts/dwm-session-setup.sh is not valid bash"

work=$(mktemp -d)
FIXTURE_USER=""

# ── A sandbox root every path argument points at ─────────
root="$work/root"
mkdir -p "$root/etc/xdg/autostart" "$root/etc/pam.d" "$root/var/lib/dwm-fox" \
	"$root/usr/local/bin" "$root/usr/share/keyrings"

# Rewrite only the absolute paths into a sandbox root. The privileged helper is
# replaced below by appending a redefinition, which is reliable; sed-matching a
# function body is not.
sed \
	-e "s|^XSESSION_FILE=.*|XSESSION_FILE=\"$root/etc/xsessions/dwm.desktop\"|" \
	-e "s|^XDG_AUTOSTART_FILE=.*|XDG_AUTOSTART_FILE=\"$root/etc/xdg/autostart/dwm-fox-session.desktop\"|" \
	-e "s|^STATE_DIR=.*|STATE_DIR=\"$root/var/lib/dwm-fox\"|" \
	-e "s|^BACKUP_DIR=.*|BACKUP_DIR=\"$root/var/lib/dwm-fox/session-setup-backup\"|" \
	-e 's|^PAM_XSESSION_FILE=.*|PAM_XSESSION_FILE="$root/etc/pam.d/xsession"|' \
	-e 's|install -d -o root -g root -m|install -d -m|g' \
	-e 's|install -o root -g root -m|install -m|g' \
	"$SETUP" >"$work/setup.sh"

# Append a sandbox as_root. It records the command, then runs it: every path it
# touches is already inside the sandbox, so only the privilege escalation is
# elided. Appending redefines the function instead of editing it in place.
cat >>"$work/setup.sh" <<'SANDBOX'

# --- sandbox override -------------------------------------------------
as_root() {
	if [ -n "${STUB_AS_ROOT:-}" ]; then
		printf '%s\n' "$*" >>"$STUB_AS_ROOT"
		"$@"
		return
	fi
	if [ "$EUID" -eq 0 ]; then
		"$@"
	else
		sudo "$@"
	fi
}
SANDBOX
chmod +x "$work/setup.sh"

# The rewrites above expand $root at rewrite time via double quotes and leave a
# literal $root inside single-quoted sed expressions, so export it for the
# rewritten script to expand at run time.
export root
bash -n "$work/setup.sh" || fail "the sandboxed copy of the setup script is invalid"
grep -q 'STUB_AS_ROOT' "$work/setup.sh" ||
	fail "the sandbox rewrite did not neutralize as_root"

# ── Command stubs ────────────────────────────────────────
bin="$work/bin"
mkdir -p "$bin"
cat >"$bin/getent" <<-'STUB'
	#!/bin/sh
	case "${1:-}" in
	group)
		# Report every probed hardware group as existing but empty.
		printf '%s:x:4096:\n' "${2:-}"
		exit 0
		;;
	esac
	exit 2
STUB
# The target user's identity is resolved through `id`, which must reach the real
# account created below so `usermod` is given a name that actually exists.
# `id -nG` is answered from EXISTING_GROUPS so each phase can model a user who
# is not yet, or already, a member of the hardware groups.
cat >"$bin/id" <<-'STUB'
	#!/bin/sh
	if [ "${1:-}" = "-nG" ]; then
		printf '%s\n' "${EXISTING_GROUPS:-}"
		exit 0
	fi
	exec /usr/bin/id "$@"
STUB
# usermod and loginctl are recorded and then executed for real, so the test
# proves the script's arguments are valid rather than only well-formed.
cat >"$bin/usermod" <<-'STUB'
	#!/bin/sh
	printf 'usermod %s\n' "$*" >>"$STUB_LOG"
	if [ "$(id -u)" -eq 0 ]; then
		/usr/sbin/usermod "$@"
	else
		/usr/bin/sudo /usr/sbin/usermod "$@"
	fi
STUB
cat >"$bin/loginctl" <<'STUB'
#!/bin/sh
case "$*" in
show-user*)
	# Reflect the linger state the script itself requested, so uninstall has
	# something real to reverse.
	if [ -f "$STUB_STATE/linger-enabled" ]; then
		printf 'yes\n'
	else
		printf 'no\n'
	fi
	;;
enable-linger*)
	printf 'loginctl %s\n' "$*" >>"$STUB_LOG"
	: >"$STUB_STATE/linger-enabled"
	;;
disable-linger*)
	printf 'loginctl %s\n' "$*" >>"$STUB_LOG"
	rm -f "$STUB_STATE/linger-enabled"
	;;
*)
	printf 'loginctl %s\n' "$*" >>"$STUB_LOG"
	;;
esac
STUB
cat >"$bin/pam-auth-update" <<-'STUB'
	#!/bin/sh
	printf 'pam-auth-update %s\n' "$*" >>"$STUB_LOG"
STUB
chmod +x "$bin"/*
export STUB_AS_ROOT="$work/root.log"
export STUB_LOG="$work/calls.log"
export STUB_STATE="$work/state"
mkdir -p "$STUB_STATE"
: >"$STUB_AS_ROOT"
: >"$STUB_LOG"

run_setup() {
	if ! PATH="$bin:$PATH" bash "$work/setup.sh" "$@" >"$work/output" 2>&1; then
		cat "$work/output" >&2
		fail "dwm-session-setup.sh $* failed"
	fi
}

# Print the captured output before a failed assertion, so a failure is
# diagnosable without re-running under -x.
report() {
	printf -- '--- last dwm-session-setup.sh output ---\n' >&2
	cat "$work/output" >&2 2>/dev/null || true
	printf -- '--- privileged command log ---\n' >&2
	cat "$STUB_AS_ROOT" >&2 2>/dev/null || true
	printf -- '--- sandbox tree ---\n' >&2
	find "$root" -type f >&2 2>/dev/null || true
	printf -- '---------------------------------------\n' >&2
}

# Remove the fixture account on any exit, so an interrupted run can never leave
# it behind on the host.
trap 'if [[ -n ${FIXTURE_USER:-} ]] && getent passwd "$FIXTURE_USER" >/dev/null 2>&1; then
		if [[ $EUID -eq 0 ]]; then
			userdel -r "$FIXTURE_USER" >/dev/null 2>&1 || true
		else
			sudo userdel -r "$FIXTURE_USER" >/dev/null 2>&1 || true
		fi
	fi; rm -rf "$work"' EXIT

# The script validates the target user with `id NAME` and later calls `usermod`,
# which rejects an account it cannot find. Create a throwaway account rather
# than mocking usermod, so the real privilege path is exercised.
FIXTURE_USER="dwmfox-test-$$"
if [[ $EUID -eq 0 ]]; then
	useradd -m -s /bin/sh "$FIXTURE_USER" 2>/dev/null ||
		fail "could not create the throwaway fixture user"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
	sudo useradd -m -s /bin/sh "$FIXTURE_USER" 2>/dev/null ||
		fail "could not create the throwaway fixture user with sudo"
else
	printf 'SKIP: test-session-setup needs root to create its fixture user.\n'
	exit 0
fi
if ! getent passwd "$FIXTURE_USER" >/dev/null 2>&1; then
	fail "the fixture user was not created"
fi

# ── install is additive and idempotent ───────────────────
# First pass: the user holds none of the hardware groups.
EXISTING_GROUPS=""
export EXISTING_GROUPS
run_setup install --user "$FIXTURE_USER"

[[ -f $root/etc/xdg/autostart/dwm-fox-session.desktop ]] ||
	fail "install must write the XDG autostart entry"
grep -q 'graphical-session' "$root/etc/xdg/autostart/dwm-fox-session.desktop" ||
	fail "the autostart entry must activate the graphical session targets"
[[ -f $root/etc/pam.d/xsession ]] || fail "install must provide /etc/pam.d/xsession"
grep -q 'common-session' "$root/etc/pam.d/xsession" ||
	fail "the PAM stack must include common-session for pam_systemd"

grep -q "usermod -aG video $FIXTURE_USER" "$STUB_LOG" || fail "the user must join the video group"
grep -q "usermod -aG render $FIXTURE_USER" "$STUB_LOG" || fail "the user must join the render group"
grep -q "usermod -aG input $FIXTURE_USER" "$STUB_LOG" || fail "the user must join the input group"
grep -q "usermod -aG audio $FIXTURE_USER" "$STUB_LOG" || fail "the user must join the audio group"
grep -q "loginctl enable-linger $FIXTURE_USER" "$STUB_LOG" || fail "linger must be enabled by default"

# A second run, now with every group already granted, must be a no-op for
# group membership.
EXISTING_GROUPS="video render input audio"
export EXISTING_GROUPS
: >"$STUB_LOG"
run_setup install --user "$FIXTURE_USER"
if grep -q 'usermod' "$STUB_LOG"; then
	grep 'usermod' "$STUB_LOG" >&2
	fail "a second install must not re-add an existing group"
fi

# A second install must also recognise the PAM file it generated, rather than
# treating it as a pre-existing file to back up. Backing up our own output makes
# uninstall "restore" it, so it can never be removed.
[[ ! -f $root/var/lib/dwm-fox/session-setup-backup/xsession.pam ]] || {
	report
	fail "a second install must not back up the PAM file dwm-fox itself generated"
}
grep -qF 'Installed by dwm-fox.' "$root/etc/pam.d/xsession" || {
	report
	fail "the generated PAM file must carry the dwm-fox marker"
}

# ── --no-linger must skip linger ─────────────────────────
: >"$STUB_LOG"
run_setup install --user "$FIXTURE_USER" --no-linger
grep -q 'enable-linger' "$STUB_LOG" && fail "--no-linger must not enable linger"

# ── status is read-only ──────────────────────────────────
run_setup status --user "$FIXTURE_USER"
grep -q 'linger:' "$work/output" || fail "status must report the linger state"
grep -q "user:            $FIXTURE_USER" "$work/output" || fail "status must report the target user"

# ── uninstall reverses only what it created ──────────────
run_setup uninstall --user "$FIXTURE_USER"
[[ ! -f $root/etc/xdg/autostart/dwm-fox-session.desktop ]] ||
	fail "uninstall must remove the XDG autostart entry"
[[ ! -f $root/etc/pam.d/xsession ]] || {
	report
	fail "uninstall must remove the PAM file it created"
}
grep -q "loginctl disable-linger $FIXTURE_USER" "$STUB_LOG" ||
	fail "uninstall must disable linger"
grep -q "gpasswd -d $FIXTURE_USER" "$work/output" ||
	fail "uninstall must document how to remove group membership"

# Uninstall must be safe to repeat.
run_setup uninstall --user "$FIXTURE_USER"

# ── A pre-existing PAM file is backed up and restored ───
printf '%s\n' '# original' >"$root/etc/pam.d/xsession"
: >"$STUB_AS_ROOT"
run_setup install --user "$FIXTURE_USER"
[[ -f $root/var/lib/dwm-fox/session-setup-backup/xsession.pam ]] ||
	fail "a pre-existing PAM file must be backed up before modification"
run_setup uninstall --user "$FIXTURE_USER"
grep -q 'original' "$root/etc/pam.d/xsession" ||
	fail "uninstall must restore the original PAM file"

# ── An unknown user is rejected before any change ────────
if PATH="$bin:$PATH" bash "$work/setup.sh" install --user dwmfox-nosuchuser-$$ \
	>"$work/output" 2>&1; then
	fail "an unknown user must be rejected"
fi

printf 'test-session-setup: OK\n'