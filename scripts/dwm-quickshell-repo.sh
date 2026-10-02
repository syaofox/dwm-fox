#!/usr/bin/env bash
# dwm-quickshell-repo.sh — enable or disable the Quickshell apt repository.
#
# Why a third-party repository is required
# -----------------------------------------
# Quickshell is the QML engine behind the dwm-fox panel, launcher, Control
# Center, Settings and notifications. It is NOT packaged in the Ubuntu archive
# and upstream publishes source tarballs only — no release ever carried a
# binary asset. Debian unstable/testing and the Arch/Fedora archives carry
# builds, but Ubuntu has none. The upstream Quickshell documentation therefore
# points Ubuntu users at the `avengemedia/danklinux` Personal Package Archive,
# which republishes the Open Build Service `home:AvengeMedia:danklinux` project.
#
# This script enables that PPA explicitly and reversibly:
#   * the signing key is fetched from the Ubuntu keyserver,
#   * its fingerprint is checked against a pinned value,
#   * the key is dearmored into a dedicated keyring under /usr/share/keyrings,
#   * the source is written as a deb822 stanza scoped to the running suite.
#
# Re-running is safe. `uninstall` removes only the files this script created and
# only when they still match what it wrote.
#
# Usage: dwm-quickshell-repo.sh {enable|disable|status}

set -euo pipefail

PPA_OWNER="avengemedia"
PPA_NAME="danklinux"
PPA_FINGERPRINT="45FECBE587307AAA3F0A4BE9FC44813D2A7788B7"
PPA_KEYSERVER="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PPA_FINGERPRINT}"
PPA_URI="https://ppa.launchpadcontent.net/${PPA_OWNER}/${PPA_NAME}/ubuntu"

KEYRING="/usr/share/keyrings/danklinux-archive-keyring.gpg"
SOURCE_FILE="/etc/apt/sources.list.d/danklinux.sources"
MARKER="/var/lib/dwm-fox/quickshell-repo"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'
info() { printf "${CYAN:-}${GREEN}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

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

# Resolve the codename of the running release, e.g. "resolute" on Ubuntu 26.04.
release_suite() {
	if [[ -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		source /etc/os-release
		printf '%s\n' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
	fi
}

repo_enabled() {
	[[ -f $SOURCE_FILE ]] && grep -q "launchpadcontent.net/${PPA_OWNER}/${PPA_NAME}" "$SOURCE_FILE"
}

fetch_key() {
	local tmp
	tmp=$(mktemp)
	# shellcheck disable=SC2064
	trap "rm -f '$tmp'" RETURN

	if ! curl --fail --location --silent --show-error "$PPA_KEYSERVER" --output "$tmp"; then
		err "Could not download the PPA signing key from the Ubuntu keyserver."
		return 1
	fi
	if ! grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$tmp"; then
		err "The downloaded key file is not an ASCII-armored OpenPGP block."
		return 1
	fi

	# Verify the fingerprint of what was actually downloaded before trusting it.
	local actual
	actual=$(gpg --show-keys --with-colons "$tmp" 2>/dev/null |
		awk -F: '/^fpr:/ { print $10; exit }')
	if [[ $actual != "$PPA_FINGERPRINT" ]]; then
		err "Signing key fingerprint mismatch."
		err "  expected: $PPA_FINGERPRINT"
		err "  actual:   ${actual:-none}"
		return 1
	fi

	local ring
	ring=$(mktemp)
	if ! gpg --batch --yes --dearmor --output "$ring" "$tmp"; then
		rm -f "$ring"
		err "Could not dearmor the signing key."
		return 1
	fi
	as_root install -d -m 0755 "$(dirname "$KEYRING")"
	as_root install -o root -g root -m 0644 "$ring" "$KEYRING"
	rm -f "$ring"
}

enable_repo() {
	local suite
	suite=$(release_suite)
	if [[ -z $suite ]]; then
		err "Could not determine this release's codename from /etc/os-release."
		return 1
	fi

	if repo_enabled && [[ -f $KEYRING ]]; then
		ok "Quickshell repository already enabled ($PPA_OWNER/$PPA_NAME for $suite)."
		return 0
	fi

	if ! command -v gpg >/dev/null 2>&1; then
		warn "gpg is unavailable; installing gnupg for key verification."
		as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg ||
			{
				err "Could not install gnupg."
				return 1
			}
	fi

	info "Fetching and verifying the $PPA_OWNER/$PPA_NAME signing key..."
	fetch_key || return 1

	local tmp
	tmp=$(mktemp)
	cat >"$tmp" <<-EOF
		Types: deb
		URIs: $PPA_URI/ $suite main
		Suites: $suite
		Components: main
		Signed-By: $KEYRING
	EOF
	as_root install -d -m 0755 "$(dirname "$SOURCE_FILE")"
	as_root install -o root -g root -m 0644 "$tmp" "$SOURCE_FILE"
	rm -f "$tmp"

	as_root install -d -m 0755 "$(dirname "$MARKER")"
	printf 'owner=%s\nname=%s\nsuite=%s\nfingerprint=%s\n' \
		"$PPA_OWNER" "$PPA_NAME" "$suite" "$PPA_FINGERPRINT" |
		as_root tee "$MARKER" >/dev/null

	info "Refreshing apt metadata..."
	if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get update; then
		warn "apt-get update reported errors; the repository may lack this suite."
		warn "If Quickshell cannot be installed, check $SOURCE_FILE and the PPA suite list."
		return 1
	fi

	ok "Quickshell repository enabled for $suite."
}

disable_repo() {
	local removed=0

	if [[ -f $SOURCE_FILE ]]; then
		as_root rm -f "$SOURCE_FILE"
		removed=1
		ok "Removed $SOURCE_FILE."
	else
		ok "Repository source file was already absent."
	fi

	if [[ -f $KEYRING ]]; then
		as_root rm -f "$KEYRING"
		ok "Removed $KEYRING."
	fi
	if [[ -f $MARKER ]]; then
		as_root rm -f "$MARKER"
	fi

	if ((removed)); then
		info "Refreshing apt metadata..."
		as_root env DEBIAN_FRONTEND=noninteractive apt-get update || true
	fi
}

repo_status() {
	if repo_enabled; then
		printf 'enabled: %s\n' "$SOURCE_FILE"
	else
		printf 'disabled: %s is absent\n' "$SOURCE_FILE"
	fi
	if [[ -f $KEYRING ]]; then
		printf 'keyring: %s\n' "$KEYRING"
	else
		printf 'keyring: absent\n'
	fi
	local suite
	suite=$(release_suite)
	printf 'suite: %s\n' "${suite:-unknown}"
	printf 'package: '
	if command -v apt-cache >/dev/null 2>&1; then
		# No early `exit` in awk: under `set -o pipefail` an early exit would
		# hand apt-cache a SIGPIPE and fail the whole status report.
		apt-cache policy quickshell 2>/dev/null |
			awk '/Candidate:/ { if (!found) { print $2; found = 1 } }
			     END { if (!found) print "unavailable" }'
	else
		printf 'unknown\n'
	fi
}

case "${1:-status}" in
enable) enable_repo ;;
disable) disable_repo ;;
status) repo_status ;;
*)
	printf 'usage: %s {enable|disable|status}\n' "${0##*/}" >&2
	exit 2
	;;
esac