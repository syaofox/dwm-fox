#!/usr/bin/env bash
# Shared package capability map for the dwm-fox installers and diagnostics.
#
# The map is keyed by "<family>:<profile>". The debian family covers Debian and
# Ubuntu and uses Debian archive names. The fedora family is retained for
# upstream parity with dwm-fox but is not the supported platform here; see
# MIGRATION.md for the full name-by-name mapping and why each entry differs.

dwm_packages() {
	local family=$1
	local profile=$2

	case "$family:$profile" in
	debian:build)
		# apt equivalent of the Fedora build set:
		#   pkgconf-pkg-config libX11-devel libXft-devel libXinerama-devel
		#   libXrender-devel imlib2-devel libxcb-devel xcb-util-devel
		#   freetype-devel fontconfig-devel
		# libx11-xcb-dev and libxcb-res0-dev back the x11-xcb and xcb-res
		# pkg-config modules listed in config.mk; Ubuntu ships them separately.
		printf '%s\n' \
			gcc make pkgconf libx11-dev libxft-dev libxinerama-dev \
			libxrender-dev libimlib2-dev libxcb1-dev libxcb-util-dev \
			libx11-xcb-dev libxcb-res0-dev \
			libfreetype-dev libfontconfig1-dev
		;;
	debian:ci-smoke)
		dwm_packages "$family" build
		printf '%s\n' quickshell python3 dbus-daemon util-linux procps \
			xvfb xdotool x11-utils x11-xserver-utils xsettingsd \
			jq inotify-tools gawk fonts-noto-core
		;;
	debian:x11)
		# Ubuntu splits the Fedora xorg-* tools differently:
		#   xrandr/xset/xsetroot -> x11-xserver-utils
		#   setxkbmap           -> x11-xkb-utils
		#   xinput              -> xinput
		printf '%s\n' xserver-xorg xinit x11-xserver-utils xinput \
			x11-xkb-utils xkbset
		;;
	debian:runtime-required)
		# procps-ng -> procps, xprop -> x11-utils, dbus-x11 keeps its name.
		printf '%s\n' dbus-x11 curl git procps psmisc unzip util-linux \
			xclip xdotool x11-utils xdg-utils
		;;
	debian:media)
		printf '%s\n' celluloid mpv sxiv python3 desktop-file-utils
		;;
	debian:desktop)
		# quickshell comes from the official avengemedia/danklinux PPA; the
		# installer enables that repository before this profile runs.
		#   dex-autostart   -> dex
		#   libseccomp      -> libseccomp2 (runtime library bwrap links)
		#   dbus-tools      -> dbus
		#   pipewire-pulseaudio -> pipewire-audio
		#   xorg-x11-drv-libinput -> xserver-xorg-input-libinput
		#
		# The qml6-module-* runtime set is mandatory, not optional. The Ubuntu
		# quickshell package does not depend on it, because on Fedora the Qt QML
		# modules arrive with the base Qt install that Quickshell itself pulls in.
		# On Ubuntu they are separate packages, and without them every QML file
		# importing QtQuick.Layouts, QtQuick.Controls or QtQuick.Window fails to
		# load and the shell never starts.
		printf '%s\n' \
			quickshell picom python3 feh dex mate-polkit xsettingsd \
			bubblewrap libseccomp2 alsa-utils brightnessctl dbus \
			inotify-tools jq pulseaudio-utils pipewire pavucontrol \
			pipewire-audio pipewire-bin wireplumber libnotify-bin \
			xserver-xorg-input-libinput bluez blueman \
			playerctl upower power-profiles-daemon flatpak \
			xdg-desktop-portal-gtk
		;;
	debian:screenlock-optional)
		# NOT part of the desktop profile on purpose. The Ubuntu light-locker
		# package has a hard "Depends: lightdm", so installing it pulls a
		# display manager in and its postinst enables the service. That would
		# silently override --no-display-manager, so the caller must opt in.
		printf '%s\n' light-locker
		;;
	debian:qt-runtime)
		# Qt Quick runtime modules for the Quickshell panel. Keep in sync with
		# the imports found in config/quickshell; `check-package-map.sh` and
		# `tests/test-qt-runtime-modules.sh` assert both sides agree.
		printf '%s\n' \
			qml6-module-qtquick \
			qml6-module-qtquick-controls \
			qml6-module-qtquick-layouts \
			qml6-module-qtquick-window \
			qml6-module-qtquick-templates \
			qml6-module-qtquick-dialogs \
			qml6-module-qtquick-shapes \
			qml6-module-qtqml-workerscript \
			qml6-module-qt-labs-platform \
			qml6-module-qtmultimedia
		;;
	debian:system-management)
		# python3-gobject -> python3-gi
		# python3-rpm     -> dropped (dpkg-query replaces rpm queries)
		# PackageKit-glib  -> gir1.2-packagekitglib-1.0
		printf '%s\n' \
			packagekit gir1.2-packagekitglib-1.0 python3-gi \
			accountsservice cups system-config-printer
		;;
	debian:system-management-optional)
		# dnfdragora has no Debian equivalent. lxqt-admin covers user accounts
		# and time settings; software-properties-gtk is Ubuntu's authoritative
		# "Software & Updates" repository front end.
		printf '%s\n' lxqt-admin software-properties-gtk
		;;
	debian:source-update)
		printf '%s\n' xsettingsd xkbset bubblewrap libseccomp2 network-manager
		;;
	debian:desktop-optional)
		# gvfs-smb     -> gvfs-fuse (the SMB backend on Ubuntu)
		# NetworkManager-wifi -> network-manager
		# gnome-keyring-pam is not a separate archive package; PAM wiring is
		# written by install.sh instead.
		printf '%s\n' \
			thunar gvfs gvfs-fuse tumbler thunar-archive-plugin \
			file-roller xdg-user-dirs gnome-keyring network-manager \
			rsync
		;;
	debian:gaming)
		# No i686 multilib packages exist, so the 32-bit Mangohud and
		# Gamemode variants are intentionally absent.
		if [[ ${ARCH:-$(uname -m)} == x86_64 ]]; then
			printf '%s\n' steam-installer gamescope gamemode mangohud
		fi
		;;
	debian:theme)
		# dconf -> dconf-gsettings-backend
		printf '%s\n' dconf-gsettings-backend adwaita-icon-theme \
			papirus-icon-theme
		;;
	debian:theme-gtk)
		# arc-theme exists on Ubuntu. The numix, deepin, bluebird and yaru
		# themes do not; the bundled assets/themes/Dwm-* palettes cover the
		# same visual role and are installed by the Makefile.
		printf '%s\n' arc-theme
		;;
	debian:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	debian:fonts)
		# google-noto-color-emoji-fonts -> fonts-noto-color-emoji
		# google-noto-sans-mono-fonts  -> fonts-noto-mono
		printf '%s\n' fonts-noto-color-emoji fonts-noto-core fonts-noto-mono
		;;
	debian:qml-development)
		printf '%s\n' qt6-declarative-dev
		;;
	debian:qml-validation)
		dwm_packages "$family" quickshell
		dwm_packages "$family" xsettingsd
		dwm_packages "$family" qml-development
		;;
	debian:quickshell)
		# Not part of any larger profile: the Quickshell UI engine. Kept
		# separate so `core` installs stay free of a third-party repository.
		printf '%s\n' quickshell
		;;
	debian:lightdm)
		printf '%s\n' lightdm slick-greeter
		;;
	debian:terminal)
		printf '%s\n' alacritty kitty
		;;
	debian:terminal-primary)
		printf '%s\n' alacritty
		;;
	debian:screenshot-optional)
		printf '%s\n' maim
		;;
	debian:display-optional)
		# Diagnostic and test helpers for a headless or virtual machine.
		printf '%s\n' xvfb x11-utils mesa-utils
		;;
	debian:required | debian:recommended | debian:optional)
		# Aggregates are de-duplicated: python3 appears in both the media and
		# desktop profiles, and apt does not need the same package twice.
		_local_dedupe=1
		case "$family:$profile" in
		debian:required)
			dwm_packages "$family" build
			dwm_packages "$family" x11
			dwm_packages "$family" runtime-required
			dwm_packages "$family" media
			;;
		debian:recommended)
			dwm_packages "$family" desktop
			dwm_packages "$family" qt-runtime
			dwm_packages "$family" system-management
			dwm_packages "$family" screenshot-optional
			dwm_packages "$family" theme
			dwm_packages "$family" theme-gtk
			dwm_packages "$family" fonts
			;;
		debian:optional)
			dwm_packages "$family" theme-optional
			dwm_packages "$family" desktop-optional
			dwm_packages "$family" system-management-optional
			;;
		esac | awk 'NF && !seen[$0]++'
		unset _local_dedupe
		return 0
		;;
	debian:full)
		{
			dwm_packages "$family" required
			dwm_packages "$family" recommended
			dwm_packages "$family" optional
			dwm_packages "$family" gaming
		} | awk 'NF && !seen[$0]++'
		return 0
		;;
	fedora:build)
		printf '%s\n' \
			gcc make pkgconf-pkg-config libX11-devel libXft-devel \
			libXinerama-devel libXrender-devel imlib2-devel libxcb-devel \
			xcb-util-devel freetype-devel fontconfig-devel
		;;
	fedora:x11)
		printf '%s\n' xorg-x11-server-Xorg xorg-x11-xinit xrandr xset xsetroot xinput setxkbmap xkbset
		;;
	fedora:runtime-required)
		printf '%s\n' dbus-x11 curl git procps-ng psmisc unzip util-linux xclip xdotool xprop xdg-utils
		;;
	fedora:media)
		printf '%s\n' celluloid mpv sxiv python3 desktop-file-utils
		;;
	fedora:desktop)
		printf '%s\n' \
			quickshell picom python3 feh dex-autostart mate-polkit xsettingsd bubblewrap libseccomp \
			alsa-utils brightnessctl dbus-tools inotify-tools jq pulseaudio-utils pipewire pavucontrol \
			pipewire-pulseaudio wireplumber libnotify light-locker xorg-x11-drv-libinput \
			bluez blueman playerctl upower power-profiles-daemon flatpak xdg-desktop-portal-gtk
		;;
	fedora:system-management)
		printf '%s\n' \
			PackageKit PackageKit-glib python3-gobject python3-rpm accountsservice cups \
			system-config-printer
		;;
	fedora:source-update)
		printf '%s\n' xsettingsd xkbset bubblewrap libseccomp NetworkManager-wifi
		;;
	fedora:desktop-optional)
		printf '%s\n' \
			Thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs gnome-keyring gnome-keyring-pam NetworkManager \
			NetworkManager-wifi rsync
		;;
	fedora:theme)
		printf '%s\n' dconf adwaita-icon-theme papirus-icon-theme
		;;
	fedora:fonts)
		printf '%s\n' google-noto-color-emoji-fonts google-noto-sans-mono-fonts
		;;
	fedora:terminal)
		printf '%s\n' alacritty kitty
		;;
	fedora:terminal-primary)
		printf '%s\n' alacritty
		;;
	fedora:screenshot-optional)
		printf '%s\n' maim
		;;
	fedora:lightdm)
		printf '%s\n' lightdm slick-greeter
		;;
	fedora:required)
		dwm_packages "$family" build
		dwm_packages "$family" x11
		dwm_packages "$family" runtime-required
		dwm_packages "$family" media
		;;
	fedora:recommended)
		dwm_packages "$family" desktop
		dwm_packages "$family" system-management
		dwm_packages "$family" screenshot-optional
		dwm_packages "$family" theme
		dwm_packages "$family" fonts
		;;
	fedora:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
		dwm_packages "$family" system-management-optional
		;;
	fedora:full)
		dwm_packages "$family" required
		dwm_packages "$family" recommended
		dwm_packages "$family" optional
		;;
	*)
		return 1
		;;
	esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
	[[ $# == 2 ]] || {
		printf 'usage: %s FAMILY PROFILE\n' "$0" >&2
		exit 2
	}
	dwm_packages "$1" "$2"
	exit $?
fi

dwm_install_package_profile() {
	local profile=$1
	local packages=()
	local package

	while IFS= read -r package; do
		[[ -n $package ]] || continue
		if [[ $package == power-profiles-daemon ]] && dwm_power_profiles_provider_installed; then
			printf '%s\n' \
				'Retaining installed Power Profiles provider (ppd-service); skipping power-profiles-daemon.' >&2
			continue
		fi
		packages+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#packages[@]} == 0)); then
		return 0
	fi

	install_packages "${packages[@]}"
}

dwm_power_profiles_provider_installed() {
	package_installed power-profiles-daemon
}

dwm_install_available_package_profile() {
	local profile=$1
	local package
	local status=0

	while IFS= read -r package; do
		[[ -n $package ]] || continue
		if ! install_optional_package "$package"; then
			printf 'Skipping unavailable optional package: %s\n' "$package" >&2
			status=1
		fi
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	return "$status"
}

dwm_install_first_available_package() {
	local package

	for package in "$@"; do
		if install_optional_package "$package" 2>/dev/null; then
			return 0
		fi
	done

	return 1
}

dwm_install_first_available_profile() {
	local profile=$1
	local packages=()
	local package

	while IFS= read -r package; do
		[[ -n $package ]] && packages+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#packages[@]} == 0)); then
		return 1
	fi

	dwm_install_first_available_package "${packages[@]}"
}