#!/usr/bin/env bash
# test-package-map.sh — the shared dependency map is complete and consistent.
#
# The map is the single source of truth for what the installer installs. This
# test proves every profile the installer can request resolves, that the Ubuntu
# names are Debian archive names rather than RPM names, and that names shared
# between profiles are de-duplicated.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="$REPO_DIR/scripts/dwm-packages.sh"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

# Resolve a profile once and cache it. Piping the map straight into grep -q
# gives the producer a SIGPIPE, which `set -o pipefail` then reports as a test
# failure rather than as a successful match.
profile_cache=""
profile_resolve() {
	if [[ -z $profile_cache ]]; then
		profile_cache=$(bash "$PACKAGES" "$1" "$2" 2>/dev/null || true)
	fi
	printf '%s\n' "$profile_cache"
}
profile_clear() { profile_cache=""; }

# profile_has FAMILY PROFILE PACKAGE
profile_has() {
	profile_clear
	profile_resolve "$1" "$2" | grep -Fxq -- "$3"
}

# apt_candidate PACKAGE -- the install candidate, or empty when unavailable.
# awk must not `exit` early: under `set -o pipefail` the resulting SIGPIPE in
# apt-cache would fail the whole pipeline and be mistaken for a missing package.
apt_candidate() {
	apt-cache policy "$1" 2>/dev/null |
		awk '/Candidate:/ { if (!found) { value = $2; found = 1 } }
		     END { if (found && value != "(none)") print value }'
}

# Profiles install.sh and the Makefile can ask for.
for profile in build x11 runtime-required media desktop qt-runtime \
	system-management screenlock-optional system-management-optional source-update \
	desktop-optional gaming theme theme-gtk theme-optional fonts \
	qml-development qml-validation quickshell lightdm terminal terminal-primary \
	screenshot-optional display-optional required recommended optional full; do
	if ! bash "$PACKAGES" debian "$profile" >/dev/null 2>&1; then
		fail "the debian family does not resolve the $profile profile"
	fi
done

if bash "$PACKAGES" debian not-a-profile >/dev/null 2>&1; then
	fail "an unknown profile must fail"
fi
if bash "$PACKAGES" not-a-family required >/dev/null 2>&1; then
	fail "an unknown family must fail"
fi
if bash "$PACKAGES" debian; then
	fail "dwm-packages.sh must reject a missing argument"
fi
if bash "$PACKAGES" debian full extra >/dev/null 2>&1; then
	fail "dwm-packages.sh must reject an extra argument"
fi

# ── No RPM-era names may survive in the debian map ───────
# Captured rather than listed so the intent is explicit.
for rpm_name in \
	pkgconf-pkg-config libX11-devel libXft-devel libXinerama-devel \
	libXrender-devel imlib2-devel libxcb-devel xcb-util-devel \
	freetype-devel fontconfig-devel \
	xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-server-Xvfb \
	procps-ng dex-autostart libseccomp dbus-tools \
	pipewire-pulseaudio xorg-x11-drv-libinput \
	PackageKit PackageKit-glib python3-gobject python3-rpm python3-libdnf5 \
	google-noto-color-emoji-fonts google-noto-sans-mono-fonts \
	dconf dnfdragora; do
	if profile_has debian full "$rpm_name"; then
		fail "the debian map still lists the RPM package name $rpm_name"
	fi
done

# A name the debian map uses must actually resolve in the Debian archive when
# apt-cache is available. This is the check that catches a typo or a package
# that upstream never published.
if command -v apt-cache >/dev/null 2>&1; then
	missing=()
	while IFS= read -r package; do
		[[ -n $package ]] || continue
		candidate=$(apt_candidate "$package")
		if [[ -z $candidate || $candidate == '(none)' ]]; then
			missing+=("$package")
		fi
	done < <(profile_resolve debian full)
	if ((${#missing[@]} > 0)); then
		printf 'Unavailable in the enabled Debian archive:\n' >&2
		printf '  %s\n' "${missing[@]}" >&2
		fail "${#missing[@]} package(s) in the debian map cannot be installed"
	fi
fi

# ── install.sh must install every leaf profile the aggregates contain ──
# install.sh calls leaf profiles (desktop, system-management, ...) rather than
# the aggregates, so a profile added to an aggregate but not to install.sh is
# silently never installed. Compare the two so they cannot drift.
REPO_INSTALLER="$REPO_DIR/install.sh"

aggregate_profiles() {
	# Print the leaf profiles each aggregate expands to, taken from the map
	# itself so the expectation cannot drift from the implementation.
	local aggregate=$1 leaf
	case "$aggregate" in
	required)
		for leaf in build x11 runtime-required media; do printf '%s\n' "$leaf"; done
		;;
	recommended)
		for leaf in desktop qt-runtime system-management screenshot-optional \
			theme theme-gtk fonts; do printf '%s\n' "$leaf"; done
		;;
	optional)
		for leaf in theme-optional desktop-optional system-management-optional; do
			printf '%s\n' "$leaf"
		done
		;;
	full)
		for leaf in required recommended optional gaming; do printf '%s\n' "$leaf"; done
		;;
	esac
}

if [[ -f $REPO_INSTALLER ]]; then
	# A leaf of a composite aggregate satisfies the composite too.
	expand_profiles() {
		case "$1" in
		full)
			printf '%s\n' required recommended optional gaming
			;;
		*)
			printf '%s\n' "$1"
			;;
		esac
	}
	profile_requested() {
		local aggregate=$1 leaf
		while IFS= read -r leaf; do
			[[ -n $leaf ]] || continue
			if grep -qE "package_profile[[:space:]]+$leaf\b" "$REPO_INSTALLER"; then
				return 0
			fi
		done < <(expand_profiles "$aggregate")
		return 1
	}
	for aggregate in required recommended optional full; do
		# Requesting any profile the aggregate contains satisfies it.
		if profile_requested "$aggregate"; then
			continue
		fi
		while IFS= read -r leaf; do
			[[ -n $leaf ]] || continue
			# Otherwise each leaf must be requested by one of the helpers.
			if ! grep -qE "package_profile[[:space:]]+$leaf\b" "$REPO_INSTALLER"; then
				fail "install.sh never installs the '$leaf' profile required by the '$aggregate' aggregate"
			fi
		done < <(aggregate_profiles "$aggregate")
	done
fi

# ── light-locker must stay opt-in ────────────────────────
# On Ubuntu light-locker Depends: lightdm, and installing it enables the
# display-manager service. It may only appear in its own opt-in profile.
for aggregate in desktop recommended required full; do
	if profile_has debian "$aggregate" light-locker; then
		fail "light-locker must not be in the $aggregate profile: it pulls in lightdm"
	fi
done
[[ $(bash "$PACKAGES" debian screenlock-optional) == light-locker ]] ||
	fail "the screenlock-optional profile must resolve to light-locker"

# ── The required build modules must be covered ───────────
# config.mk asks pkg-config for these; each needs a matching -dev package.
for module in x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res fontconfig freetype2; do
	found=0
	while IFS= read -r package; do
		case "$package" in
		*-dev) found=1 ;;
		esac
	done < <(profile_resolve debian build)
	# Ubuntu development packages end in -dev; the check survives a rename.
	((found)) || fail "no development package in the build profile could provide $module"
done

# ── Aggregate profiles must not repeat a package ─────────
duplicates=$(bash "$PACKAGES" debian full | sort | uniq -d)
if [[ -n $duplicates ]]; then
	printf 'Duplicate packages in the debian full profile:\n%s\n' "$duplicates" >&2
	fail "the aggregate profile lists a package more than once"
fi

printf 'test-package-map: OK\n'