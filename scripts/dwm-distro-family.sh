#!/bin/sh
# dwm-distro-family.sh — print the dependency-map family for a distribution.
#
# The shared dependency map in dwm-packages.sh is keyed by "<family>:<profile>".
# This script is the single place that maps an /etc/os-release ID onto a family,
# so the Makefile, the installer, the diagnostics and the tests cannot disagree.
#
# Usage:
#   dwm-distro-family.sh            # detect from /etc/os-release
#   dwm-distro-family.sh --id <ID>  # map an explicit ID (for tests)
#
# Exit status: 0 on success, 2 on usage error.

set -eu

OS_RELEASE_FILE="/etc/os-release"
if [ "${DWM_TEST_MODE:-0}" = 1 ] && [ -n "${DWM_OS_RELEASE:-}" ]; then
	OS_RELEASE_FILE=$DWM_OS_RELEASE
fi

distro_id=""
explicit_id=false
case "${1:-}" in
--id)
	[ $# -eq 2 ] || {
		printf 'usage: %s [--id ID]\n' "${0##*/}" >&2
		exit 2
	}
	# An explicitly supplied ID is authoritative, including an empty one: the
	# caller asked about that value, so do not silently fall back to the host.
	distro_id=$2
	explicit_id=true
	;;
"") ;;
*)
	printf 'usage: %s [--id ID]\n' "${0##*/}" >&2
	exit 2
	;;
esac

if [ "$explicit_id" = false ] && [ -r "$OS_RELEASE_FILE" ]; then
	distro_id=$(
		awk -F= '
			$1 == "ID" {
				value = substr($0, index($0, "=") + 1)
				gsub(/^"|"$/, "", value)
				print value
				exit
			}
		' "$OS_RELEASE_FILE"
	)
fi

case "$distro_id" in
fedora)
	printf 'fedora\n'
	;;
ubuntu | debian | linuxmint | pop | elementary)
	printf 'debian\n'
	;;
*)
	printf 'unknown\n'
	;;
esac