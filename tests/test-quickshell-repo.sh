#!/usr/bin/env bash
# test-quickshell-repo.sh — Quickshell repository provisioning is pinned and
# reversible.
#
# Quickshell is the one hard external dependency of the desktop shell, and it
# comes from a third-party PPA rather than the Debian archive. These assertions
# cover the parts that make that acceptable: a pinned signing-key fingerprint, a
# suite-scoped deb822 source, no silent changes for the core profile, and a
# disable path that removes only what enable created.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$REPO_DIR/scripts/dwm-quickshell-repo.sh"
PACKAGES="$REPO_DIR/scripts/dwm-packages.sh"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -x $REPO ]] || fail "scripts/dwm-quickshell-repo.sh is missing or not executable"
bash -n "$REPO" || fail "scripts/dwm-quickshell-repo.sh is not valid bash"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ── The signing key must be pinned ────────────────────────
fingerprint=$(sed -n 's/^PPA_FINGERPRINT="\(.*\)"$/\1/p' "$REPO")
[[ -n $fingerprint ]] || fail "the PPA signing key fingerprint must be pinned in the script"
[[ $fingerprint =~ ^[0-9A-F]{40}$ ]] || fail "the pinned fingerprint must be 40 hex digits"
grep -q "^PPA_KEYSERVER=.*keyserver.ubuntu.com" "$REPO" ||
	fail "the signing key must be fetched from the Ubuntu keyserver"
grep -q '^PPA_OWNER="avengemedia"' "$REPO" ||
	fail "the repository owner must match the documented upstream PPA"
grep -q '^PPA_NAME="danklinux"' "$REPO" ||
	fail "the repository name must match the documented upstream PPA"

# The script must verify the fingerprint before trusting the downloaded key.
grep -qi 'fingerprint mismatch' "$REPO" ||
	fail "the script must verify the downloaded key fingerprint"
grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$REPO" ||
	fail "the script must confirm the download is an armored key"

# ── The source must be scoped to the running suite ────────
# The stanza is indented inside a heredoc, so match on content, not column.
grep -qE '^[[:space:]]*Types:[[:space:]]*deb$' "$REPO" ||
	fail "the source must use the deb822 format"
grep -qE '^[[:space:]]*Suites:[[:space:]]*\$suite$' "$REPO" ||
	fail "the source must be scoped to the running release suite"
grep -qE '^[[:space:]]*Signed-By:' "$REPO" ||
	fail "the source must pin its signing key"
if grep -qE '^[[:space:]]*(deb|deb-src)[[:space:]]+https?://' "$REPO"; then
	fail "the source must not use the legacy one-line format"
fi

# ── Paths must be explicit and root-owned ────────────────
grep -q '^KEYRING="/usr/share/keyrings/danklinux-archive-keyring.gpg"$' "$REPO" ||
	fail "the keyring must live in /usr/share/keyrings"
grep -q '^SOURCE_FILE="/etc/apt/sources.list.d/danklinux.sources"$' "$REPO" ||
	fail "the source must live in a single named file under /etc/apt/sources.list.d"
grep -q 'install -o root -g root -m 0644' "$REPO" ||
	fail "both the keyring and the source must be installed root-owned"

# ── status must not change anything ──────────────────────
# The report runs before and after, and the apt source tree must be untouched.
sources_before=$(md5sum /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null |
	sort | md5sum || true)
PATH="$work:$PATH" bash "$REPO" status >"$work/status" 2>&1 ||
	fail "status must succeed"
grep -q 'suite:' "$work/status" || fail "status must report the resolved suite"
grep -q 'package:' "$work/status" || fail "status must report package availability"
sources_after=$(md5sum /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null |
	sort | md5sum || true)
[[ $sources_before == "$sources_after" ]] ||
	fail "status must not modify the apt source configuration"

# ── Usage must be enforced ───────────────────────────────
if bash "$REPO" bogus >/dev/null 2>&1; then
	fail "an unknown subcommand must fail"
fi

# ── The desktop profile must depend on quickshell ────────
bash "$PACKAGES" debian desktop | grep -Fxq quickshell ||
	fail "the desktop profile must install quickshell"
bash "$PACKAGES" debian quickshell | grep -Fxq quickshell ||
	fail "the standalone quickshell profile must resolve"

# ── The core profile must stay free of the third-party repository ──
if bash "$PACKAGES" debian required | grep -Fxq quickshell; then
	fail "the required profile must not pull quickshell from a third-party repository"
fi

# ── install.sh must enable the repository before using it ─
installer="$REPO_DIR/install.sh"
grep -q 'dwm-quickshell-repo.sh" enable' "$installer" ||
	fail "install.sh must enable the Quickshell repository before installing the desktop profile"
grep -q 'dwm-quickshell-version-check' "$installer" ||
	fail "install.sh must verify the Quickshell version after installing"

printf 'test-quickshell-repo: OK\n'