#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# dwm-utils.sh — Shared utility library for dwm-fox
# Source this file from other scripts:
#   source "$(dirname "$0")/dwm-utils.sh"
#
# Supported families:
#   debian  — Debian and Ubuntu (apt)
#   fedora  — Fedora (dnf)  [kept for upstream parity; untested here]
#
# Ported from dwm-fox. See MIGRATION.md for the Fedora -> Debian/Ubuntu
# package-manager mapping and the rationale behind each branch.
# ─────────────────────────────────────────────────────────

# ── Distribution and package manager ────────────────────
DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unknown"
DWM_PACKAGE_COMMAND=()
OS_RELEASE_FILE="/etc/os-release"
if [[ ${DWM_TEST_MODE:-0} == 1 && -n ${DWM_OS_RELEASE:-} ]]; then
	OS_RELEASE_FILE=$DWM_OS_RELEASE
fi

if [[ -r $OS_RELEASE_FILE ]]; then
	# shellcheck disable=SC1090
	source "$OS_RELEASE_FILE"
	DISTRO_ID="${ID:-unknown}"
	DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
fi

case "$DISTRO_ID" in
fedora)
	DISTRO_FAMILY="fedora"
	;;
ubuntu | debian | linuxmint | pop | elementary)
	DISTRO_FAMILY="debian"
	;;
esac

# Ubuntu needs a non-interactive apt front end. Keep this in the environment
# rather than as a global export so a caller can still override it.
APT_ENV=(env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical)

case "$DISTRO_FAMILY" in
debian)
	if ((EUID == 0)); then
		DWM_PACKAGE_COMMAND=("${APT_ENV[@]}" apt-get install -y)
	else
		DWM_PACKAGE_COMMAND=(sudo "${APT_ENV[@]}" apt-get install -y)
	fi
	PKG_CMD="${DWM_PACKAGE_COMMAND[*]}"
	;;
fedora)
	if ((EUID == 0)); then
		DWM_PACKAGE_COMMAND=(dnf install -y)
	else
		DWM_PACKAGE_COMMAND=(sudo dnf install -y)
	fi
	PKG_CMD="${DWM_PACKAGE_COMMAND[*]}"
	;;
*)
	PKG_CMD="unavailable"
	;;
esac
export PKG_CMD

# dnf asks nothing; apt must not stop on a conffile or a replaced file prompt.
dwm_package_install_defaults() {
	case "$DISTRO_FAMILY" in
	debian)
		# -o Dpkg::Options::=--force-confdef keeps the packaged default on an
		# unchanged conffile instead of opening an interactive editor.
		printf '%s\n' \
			-o=Dpkg::Options::=--force-confdef \
			-o=Dpkg::Options::=--force-confold
		;;
	esac
}

install_packages() {
	local extra=()
	mapfile -t extra < <(dwm_package_install_defaults)

	case "$DISTRO_FAMILY" in
	debian)
		"${DWM_PACKAGE_COMMAND[@]}" "${extra[@]}" "$@"
		;;
	fedora)
		"${DWM_PACKAGE_COMMAND[@]}" "$@"
		;;
	*)
		printf 'Unsupported distribution: %s (Debian/Ubuntu is required)\n' "$DISTRO_NAME" >&2
		return 1
		;;
	esac
}

# dnf uses RPM architecture suffixes in queries; dpkg does not. Callers pass a
# plain package name, so the arch-qualified form is only probed on Fedora.
package_available() {
	case "$DISTRO_FAMILY" in
	debian)
		# A Candidate line means the archive can install it. When only a
		# virtual package is satisfiable apt still reports a candidate.
		apt-cache policy "$1" 2>/dev/null |
			awk '/Candidate:/ { print $2 }' |
			grep -qv '(none)'
		;;
	fedora)
		local package_arch=${1##*.}
		case "$package_arch" in
		i686 | x86_64 | aarch64)
			dnf -q repoquery --available --qf '%{name}.%{arch}' "$1" 2>/dev/null |
				command grep -Fxq "$1"
			;;
		*)
			dnf -q repoquery --available --qf '%{name}' "$1" 2>/dev/null |
				command grep -Fxq "$1"
			;;
		esac
		;;
	*)
		return 1
		;;
	esac
}

# True when dpkg has the package in the "install ok installed" state. Arch
# qualifiers and virtual packages resolve to "not installed".
package_installed() {
	case "$DISTRO_FAMILY" in
	debian)
		local status
		status=$(dpkg-query -W -f='${db:Status-Status}\n' "$1" 2>/dev/null) || return 1
		[[ $status == installed ]]
		;;
	fedora)
		rpm -q --quiet -- "$1" >/dev/null 2>&1
		;;
	*)
		return 1
		;;
	esac
}

install_optional_package() {
	local package=$1

	if package_available "$package"; then
		install_packages "$package"
		return
	fi

	printf 'Optional package is unavailable in enabled repositories: %s\n' "$package" >&2
	return 1
}

# ── Hardware Detection ──────────────────────────────────

# Detect GPU type: nvidia, amd, intel, or unknown
detect_gpu() {
	if command -v lspci &>/dev/null; then
		local vga
		vga=$(lspci 2>/dev/null | command grep -i 'vga\|3d\|display' || true)
		if echo "$vga" | command grep -qi nvidia; then
			echo "nvidia"
		elif echo "$vga" | command grep -qi 'amd\|radeon'; then
			echo "amd"
		elif echo "$vga" | command grep -qi intel; then
			echo "intel"
		else
			echo "unknown"
		fi
	else
		echo "unknown"
	fi
}

# Detect battery device name (e.g., BAT0, BAT1)
detect_battery() {
	command ls /sys/class/power_supply/ 2>/dev/null | command grep -E '^BAT[0-9]' | head -1
}

# Detect AC adapter name (e.g., ACAD, AC0, ADP1)
detect_adapter() {
	command ls /sys/class/power_supply/ 2>/dev/null | command grep -Ev '^BAT' | head -1
}

# Detect if running on a laptop (has battery)
is_laptop() {
	[ -n "$(detect_battery)" ]
}

# Detect first available terminal emulator
detect_terminal() {
	for t in dwmterm alacritty kitty st warp-terminal xterm; do
		if command -v "$t" &>/dev/null; then
			echo "$t"
			return
		fi
	done
	echo "xterm"
}