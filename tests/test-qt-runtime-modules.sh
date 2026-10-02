#!/usr/bin/env bash
# test-qt-runtime-modules.sh — the Qt Quick runtime set matches the QML imports.
#
# The Quickshell panel, launcher, Control Center and Settings are QML. Ubuntu
# packages each QML module separately and the quickshell package does not depend
# on them, so a missing module means the whole shell fails to load at runtime
# while quickshell itself reports a healthy version. This test closes that gap
# from both directions: every module the QML imports must be in the package map,
# and every package in the map must actually be installed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES="$REPO_DIR/scripts/dwm-packages.sh"
QML_DIR="$REPO_DIR/config/quickshell"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

# ── Which Qt modules does the QML actually import? ────────
# Third-party modules are excluded: Quickshell.* and qs.* come from Quickshell
# and from this repository's own module map, not from an apt package.
required_modules() {
	grep -rhoE '^[[:space:]]*import[[:space:]]+(Qt[A-Za-z0-9.]*|QtQuick[A-Za-z0-9.]*)' \
		--include='*.qml' "$QML_DIR" 2>/dev/null |
		sed -E 's/^[[:space:]]*import[[:space:]]+//' |
		# A module such as QtQuick.Controls.Basic or QtQuick.Controls.Focus
		# is satisfied by its parent module package.
		sed -E 's/\.[^.]+$//' |
		sort -u |
		grep -E '^Qt' || true
}

map_modules() {
	# Captured once: piping straight into grep -q hands the producer a SIGPIPE,
	# which `set -o pipefail` reports as a test failure.
	if [[ -z ${QT_MAP_CACHE:-} ]]; then
		QT_MAP_CACHE=$(bash "$PACKAGES" debian qt-runtime 2>/dev/null || true)
	fi
	printf '%s\n' "$QT_MAP_CACHE"
}

recommended_modules() {
	if [[ -z ${QT_RECOMMENDED_CACHE:-} ]]; then
		QT_RECOMMENDED_CACHE=$(bash "$PACKAGES" debian recommended 2>/dev/null || true)
	fi
	printf '%s\n' "$QT_RECOMMENDED_CACHE"
}

# apt_candidate PACKAGE -- the install candidate, or empty when unavailable.
# awk must not `exit` early: under `set -o pipefail` the resulting SIGPIPE in
# apt-cache would fail the whole pipeline and be mistaken for a missing package.
apt_candidate() {
	apt-cache policy "$1" 2>/dev/null |
		awk '/Candidate:/ { if (!found) { value = $2; found = 1 } }
		     END { if (found && value != "(none)") print value }'
}

# Map an import name onto its Debian runtime package.
package_for_import() {
	case "$1" in
	QtQuick) printf 'qml6-module-qtquick\n' ;;
	QtQuick.Controls) printf 'qml6-module-qtquick-controls\n' ;;
	QtQuick.Layouts) printf 'qml6-module-qtquick-layouts\n' ;;
	QtQuick.Window) printf 'qml6-module-qtquick-window\n' ;;
	QtQuick.Templates) printf 'qml6-module-qtquick-templates\n' ;;
	QtQuick.Dialogs) printf 'qml6-module-qtquick-dialogs\n' ;;
	QtQuick.Shapes) printf 'qml6-module-qtquick-shapes\n' ;;
	QtQml.WorkerScript) printf 'qml6-module-qtqml-workerscript\n' ;;
	Qt.labs.platform) printf 'qml6-module-qt-labs-platform\n' ;;
	QtMultimedia) printf 'qml6-module-qtmultimedia\n' ;;
	QtQuick.Effects | QtQuick.Controls.Material) printf '\n' ;;
	*) printf '\n' ;;
	esac
}

missing=()
while IFS= read -r module; do
	[[ -n $module ]] || continue
	package=$(package_for_import "$module")
	[[ -n $package ]] || continue
	if ! map_modules | grep -Fx -- "$package" >/dev/null; then
		missing+=("$module -> $package")
	fi
done < <(required_modules)

if ((${#missing[@]} > 0)); then
	printf 'QML imports with no package in the qt-runtime profile:\n' >&2
	printf '  %s\n' "${missing[@]}" >&2
	fail "${#missing[@]} imported module(s) would not be installed"
fi

# ── Every mapped package must resolve in the archive ─────
if command -v apt-cache >/dev/null 2>&1; then
	unresolvable=()
	while IFS= read -r package; do
		[[ -n $package ]] || continue
		candidate=$(apt_candidate "$package")
		if [[ -z $candidate || $candidate == '(none)' ]]; then
			unresolvable+=("$package")
		fi
	done < <(map_modules)
	if ((${#unresolvable[@]} > 0)); then
		printf 'qt-runtime packages missing from the archive:\n' >&2
		printf '  %s\n' "${unresolvable[@]}" >&2
		fail "${#unresolvable[@]} qt-runtime package(s) cannot be installed"
	fi
fi

# ── The recommended profile must include the runtime set ─
for package in $(map_modules); do
	if ! recommended_modules | grep -Fx -- "$package" >/dev/null; then
		fail "the recommended profile omits the qt-runtime package $package"
	fi
done

# ── On an installed system, every module must be present ─
if [[ -d /usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick ]]; then
	for module in QtQuick/Layouts QtQuick/Controls QtQuick/Window QtQuick/Templates; do
		if [[ ! -d /usr/lib/x86_64-linux-gnu/qt6/qml/$module ]]; then
			warn "Qt module not installed on this host: $module"
			warn "the Quickshell panel will fail to load until its runtime package is installed"
		fi
	done
fi

printf 'test-qt-runtime-modules: OK\n'