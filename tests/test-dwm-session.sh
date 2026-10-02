#!/usr/bin/env bash
# test-dwm-session.sh — the session launcher repairs a bare login environment.
#
# dwm-session is the only dwm entry point on Ubuntu Server, so its behaviour is
# asserted without an X server: XDG_RUNTIME_DIR, XDG_DATA_HOME, the single-pass
# dbus wrapper, and the relocated-prefix fallback.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$REPO_DIR/scripts/dwm-session"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -x $SESSION ]] || fail "scripts/dwm-session is missing or not executable"
sh -n "$SESSION" || fail "scripts/dwm-session is not valid POSIX sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A stub dwm that records the environment it was launched with.
cat >"$work/dwm" <<-'STUB'
	#!/bin/sh
	{
		printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-unset}"
		printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME:-unset}"
		printf 'XDG_CONFIG_HOME=%s\n' "${XDG_CONFIG_HOME:-unset}"
		printf 'DBUS=%s\n' "${DBUS_SESSION_BUS_ADDRESS:+set}"
		printf 'WRAPPED=%s\n' "${DWM_FOX_DBUS_WRAPPED:-unset}"
		printf 'ARGS=%s\n' "$*"
	} >"$DWM_STUB_OUTPUT"
STUB
chmod +x "$work/dwm"

run_session() {
	env -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME \
		-u DBUS_SESSION_BUS_ADDRESS \
		PATH="$work:$PATH" \
		HOME="$work/home" \
		DWM_FOX_DWM_BIN="$work/dwm" \
		DWM_STUB_OUTPUT="$work/out" \
		${DWM_STUB_TRACE:+"DWM_STUB_TRACE=$DWM_STUB_TRACE"} \
		"$SESSION" "$@"
}

mkdir -p "$work/home"

# A stub id reporting a uid that has no /run/user directory, so the private
# fallback path is exercised on hosts where the test user does have one.
cat >"$work/norunuser-bin" <<'EOF'
placeholder
EOF
mkdir -p "$work/stub-bin"
cat >"$work/stub-bin/id" <<-'STUB'
	#!/bin/sh
	case "${1:-}" in
	-u) printf '4242\n' ;;
	*) exit 0 ;;
	esac
STUB
chmod +x "$work/stub-bin/id"

# ── 1. A private runtime directory is created when none exists ──
rm -f "$work/out"
rm -rf "$work/dwm-fox-runtime-4242"
env -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME \
	-u DBUS_SESSION_BUS_ADDRESS \
	PATH="$work/stub-bin:$work:$PATH" \
	HOME="$work/home" TMPDIR="$work" \
	DWM_FOX_DWM_BIN="$work/dwm" \
	DWM_STUB_OUTPUT="$work/out" \
	"$SESSION" >/dev/null
grep -qx "XDG_RUNTIME_DIR=$work/dwm-fox-runtime-4242" "$work/out" || {
	sed -n '1,10p' "$work/out" >&2
	fail "a private runtime directory must be created when /run/user is absent"
}
grep -qx "XDG_DATA_HOME=$work/home/.local/share" "$work/out" || fail "XDG_DATA_HOME was not derived"
grep -qx "XDG_CONFIG_HOME=$work/home/.config" "$work/out" || fail "XDG_CONFIG_HOME was not derived"

mode=$(stat -c %a "$work/dwm-fox-runtime-4242")
[[ $mode == 700 ]] || fail "the private runtime directory must be mode 700, got $mode"

# ── 2. An existing logind runtime directory is preferred ──
mkdir -p "$work/run-user"
rm -f "$work/out"
env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u DBUS_SESSION_BUS_ADDRESS \
	PATH="$work:$PATH" HOME="$work/home" \
	XDG_RUNTIME_DIR="$work/run-user" \
	DWM_FOX_DWM_BIN="$work/dwm" DWM_STUB_OUTPUT="$work/out" \
	"$SESSION" >/dev/null
grep -qx "XDG_RUNTIME_DIR=$work/run-user" "$work/out" ||
	fail "an existing XDG_RUNTIME_DIR must be preserved"

# When /run/user/$uid exists but XDG_RUNTIME_DIR is unset, it must be adopted.
real_uid=$(id -u)
if [[ -d /run/user/$real_uid ]]; then
	rm -f "$work/out"
	env -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u DBUS_SESSION_BUS_ADDRESS \
		PATH="$work:$PATH" HOME="$work/home" \
		DWM_FOX_DWM_BIN="$work/dwm" DWM_STUB_OUTPUT="$work/out" \
		"$SESSION" >/dev/null
	grep -qx "XDG_RUNTIME_DIR=/run/user/$real_uid" "$work/out" ||
		fail "an existing /run/user directory must be adopted"
fi

# ── 3. The dbus wrapper runs exactly once ─────────────────
# DWM_FOX_DBUS_WRAPPED is exported before exec, so a re-entry through
# dbus-run-session cannot loop forever.
grep -qx 'WRAPPED=1' "$work/out" || fail "the re-entry guard must be exported"

# The stub emulates dbus-run-session by exporting a bus address and re-execing
# the remaining command. The session wrapper must land on dwm exactly once.
cat >"$work/dbus-run-session" <<-'STUB'
	#!/bin/sh
	# Real dbus-run-session starts a bus and execs the command after "--".
	printf 'invoked:%s\n' "$*" >>"$DWM_STUB_TRACE"
	[ "${1:-}" = "--" ] || exit 64
	shift
	DBUS_SESSION_BUS_ADDRESS=unix:path=/stub/bus
	export DBUS_SESSION_BUS_ADDRESS
	exec "$@"
STUB
chmod +x "$work/dbus-run-session"
: >"$work/trace"
rm -f "$work/out"
DWM_STUB_TRACE="$work/trace" run_session >/dev/null
grep -qx 'DBUS=set' "$work/out" ||
	fail "a session bus must be provided when none is exported"
[[ $(wc -l <"$work/trace") -eq 1 ]] ||
	fail "dbus-run-session must be entered exactly once, saw $(wc -l <"$work/trace") entries"
grep -q -- '--' "$work/trace" || fail "the bus must be started after the -- separator"

# With a bus already present, dbus-run-session must not be invoked again.
: >"$work/trace"
rm -f "$work/out"
env -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME \
	PATH="$work:$PATH" HOME="$work/home" \
	DBUS_SESSION_BUS_ADDRESS=unix:path=/preexisting/bus \
	DWM_STUB_TRACE="$work/trace" \
	DWM_FOX_DWM_BIN="$work/dwm" DWM_STUB_OUTPUT="$work/out" \
	"$SESSION" >/dev/null
grep -qx 'DBUS=set' "$work/out" || fail "an existing session bus must be reused"
[[ ! -s $work/trace ]] || fail "dbus-run-session must not start when a bus exists"

# ── 4. Arguments are forwarded to dwm ─────────────────────
rm -f "$work/out"
run_session -v -x >/dev/null
grep -qx 'ARGS=-v -x' "$work/out" || fail "dwm arguments were not forwarded"

# ── 5. A missing dwm is reported, not silently ignored ────
# A PATH with only id and the dbus stub: no dwm, so the "not installed" branch
# runs. dbus-run-session is present to prove the error survives the re-exec.
mkdir -p "$work/sparse-path"
ln -sf "$(command -v id)" "$work/sparse-path/id"
ln -sf "$work/dbus-run-session" "$work/sparse-path/dbus-run-session"
if env -u XDG_RUNTIME_DIR -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u DBUS_SESSION_BUS_ADDRESS \
	PATH="$work/sparse-path" HOME="$work/home" DWM_STUB_TRACE="$work/trace" \
	DWM_FOX_DWM_BIN="$work/absent-dwm" \
	"$SESSION" >/dev/null 2>"$work/err"; then
	fail "a missing dwm must not exit successfully"
fi
grep -q 'dwm is not installed' "$work/err" || {
	cat "$work/err" >&2
	fail "a missing dwm must be reported on stderr"
}

# ── 6. The xsessions entry launches this wrapper, not dwm ──
desktop="$REPO_DIR/dwm.desktop"
grep -q 'Exec=@PREFIX@/bin/dwm-session' "$desktop" ||
	fail "dwm.desktop must launch dwm-session so the session environment is prepared"

printf 'test-dwm-session: OK\n'