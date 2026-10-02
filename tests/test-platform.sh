#!/usr/bin/env bash
# test-platform.sh — platform identity contract for Debian/Ubuntu.
#
# Verifies that the distribution gate accepts this platform, rejects unknown
# identities, and that every gate the installer depends on is present.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAMILY_SCRIPT="$REPO_DIR/scripts/dwm-distro-family.sh"
UTILS="$REPO_DIR/scripts/dwm-utils.sh"
PACKAGES="$REPO_DIR/scripts/dwm-packages.sh"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ── Family mapping ───────────────────────────────────────
family() {
	sh "$FAMILY_SCRIPT" --id "$1"
}

[[ $(family ubuntu) == debian ]] || fail "ubuntu must map to the debian family"
[[ $(family debian) == debian ]] || fail "debian must map to the debian family"
[[ $(family fedora) == fedora ]] || fail "fedora must map to the fedora family"
[[ $(family arch) == unknown ]] || fail "arch must map to unknown"
[[ $(family "" ) == unknown ]] || fail "an empty ID must map to unknown"

printf '%s\n' 'ID=ubuntu' 'PRETTY_NAME="Ubuntu 26.04.1 LTS"' >"$work/ubuntu-release"
printf '%s\n' 'ID=fedora' 'VERSION_ID=44' >"$work/fedora-release"
printf '%s\n' 'ID=arch' >"$work/arch-release"

[[ $(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/ubuntu-release" sh "$FAMILY_SCRIPT") == debian ]] ||
	fail "os-release override did not yield the debian family"
[[ $(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/fedora-release" sh "$FAMILY_SCRIPT") == fedora ]] ||
	fail "fedora os-release override did not yield the fedora family"
[[ $(DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/arch-release" sh "$FAMILY_SCRIPT") == unknown ]] ||
	fail "unsupported os-release override must yield unknown"

sh "$FAMILY_SCRIPT" --id >/dev/null 2>&1 && fail "--id without a value must fail"
sh "$FAMILY_SCRIPT" --bogus >/dev/null 2>&1 && fail "an unknown option must fail"

# ── The installer must refuse a non-Debian platform ──────
# install.sh gates before touching the system; --dry-run proves the gate fires.
if [[ -x "$REPO_DIR/install.sh" ]]; then
	printf '%s\n' 'ID=arch' 'PRETTY_NAME="Arch Linux"' >"$work/arch-release"
	if DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/arch-release" \
		bash "$REPO_DIR/install.sh" --dry-run --non-interactive --profile core \
		>"$work/install-output" 2>&1; then
		fail "install.sh accepted an unsupported distribution"
	fi
	grep -q 'Unsupported distribution' "$work/install-output" || {
		cat "$work/install-output" >&2
		fail "install.sh did not report an unsupported distribution"
	}
fi

# ── Package manager wiring ───────────────────────────────
# shellcheck source=scripts/dwm-utils.sh
(
	# shellcheck disable=SC1090
	source "$UTILS"
	if [[ $DISTRO_FAMILY == debian ]]; then
		[[ ${DWM_PACKAGE_COMMAND[*]} == *apt-get* ]] ||
			fail "the debian family must install with apt-get"
	fi
	if [[ $DISTRO_FAMILY == fedora ]]; then
		[[ ${DWM_PACKAGE_COMMAND[*]} == *dnf* ]] ||
			fail "the fedora family must install with dnf"
	fi
	if [[ $DISTRO_FAMILY == unknown ]]; then
		[[ $PKG_CMD == unavailable ]] || fail "an unknown family must report an unavailable package manager"
		if install_packages anything >/dev/null 2>&1; then
			fail "install_packages must fail on an unknown family"
		fi
		if package_available anything >/dev/null 2>&1; then
			fail "package_available must fail on an unknown family"
		fi
	fi
) || fail "the shared utility contract check did not complete"

# ── No RPM tooling may remain in the active code paths ───
# Comments and the deliberately retained fedora map are allowed; any live
# subprocess call to rpm or dnf from a non-fedora-gated script is not.
for script in "$REPO_DIR/scripts/dwm-desktop-update" "$REPO_DIR/scripts/dwm-desktop-update-root" \
	"$REPO_DIR/scripts/dwm-update-center-terminal" "$REPO_DIR/scripts/pkg-scan.py"; do
	[ -f "$script" ] || continue
	if grep -qE '/usr/bin/(dnf|rpm)' "$script"; then
		fail "$(basename "$script") still invokes a Fedora package binary"
	fi
done

grep -q '/usr/bin/dnf5' "$REPO_DIR/scripts/dwm-update-center-terminal" &&
	fail "the update center must not allowlist dnf5"
grep -q '/usr/bin/apt-get' "$REPO_DIR/scripts/dwm-update-center-terminal" ||
	fail "the update center must allowlist apt-get"

# ── The dependency map must not reference the removed helpers
grep -q 'dwm-dnf-defaults' "$REPO_DIR/Makefile" && fail "the Makefile still installs dwm-dnf-defaults"
grep -q 'dwm-initial-update' "$REPO_DIR/Makefile" && fail "the Makefile still installs dwm-initial-update"

for removed in dwm-dnf-defaults dwm-initial-update dwm-initial-update-root; do
	if bash "$PACKAGES" debian full 2>/dev/null | grep -qx "$removed"; then
		fail "the dependency map still lists $removed"
	fi
done

printf 'test-platform: OK\n'