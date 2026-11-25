#!/bin/bash
# CHAI entry point
#
# Sourced by an app's launch script (PortMaster or not). After
# this, "chai" is a command the app and anything it starts can run, whether
# or not the CFW implements CHAI:
#  - The CFW ships chai: nothing to do.
#  - It doesn't: picks this CFW's retrofit profile (or the default one), runs
#    its setup, and puts bin/chai on PATH, which forwards to that profile.
#    Each profile handles its own CFW versions.
#
# Exports:
#   PATH                   with bin/ in front when retrofitting
#   CHAI_RETROFIT_PROFILE  the retrofit profile in use, or "native"
#
# Call chai_retrofit_teardown when the app exits. It undoes the profile's
# setup, and does nothing when the CFW has its own chai.

# This folder. Sourced files can't find their own path outside bash (busybox
# sh leaves BASH_SOURCE empty, which resolved to the caller's working
# directory), so a launcher can set CHAI_RETRO_DIR first.
if [ -z "$CHAI_RETRO_DIR" ] || [ ! -f "$CHAI_RETRO_DIR/chai_entry.sh" ]; then
	CHAI_RETRO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ ! -f "$CHAI_RETRO_DIR/chai_entry.sh" ]; then
	echo "CHAI: couldn't find chai_retrofit (got ${CHAI_RETRO_DIR}), set CHAI_RETRO_DIR before sourcing chai_entry.sh" >&2
fi

# Picks the retrofit profile from files the CFW ships, so it works whether or
# not the app was launched through PortMaster. The markers follow PortMaster's
# own CFW_NAME detection (PortMaster/device_info.txt in PortMaster-GUI), plus
# NextUI, which PortMaster doesn't recognize.
_chai_os_release_has() { # <pattern>
	grep -qi "$1" /etc/os-release /usr/lib/os-release 2>/dev/null
}

_chai_detect_profile() {
	# Spruce first: it runs on top of other systems' bases (Miyoo/TrimUI stock,
	# Debian on dArkMoss), so their markers can show up too
	if [ -f /mnt/SDCARD/spruce/spruce ]; then
		echo Spruce
	elif [ -f /mnt/SDCARD/.system/version.txt ] && grep -q "NextUI" /mnt/SDCARD/.system/version.txt 2>/dev/null; then
		echo NextUI
	elif [ -f /opt/muos/config/system/version ] || [ -f /opt/muos/config/version.txt ] ||
		[ -d /opt/muos/script ] || grep -qiE '^(ID=muos|NAME=MustardOS)' /etc/os-release 2>/dev/null; then
		echo MustardOS
	# JELOS is ROCKNIX's predecessor, with the same logind and settings layout
	elif [ -f /etc/rocknix-release ] || [ -f /storage/.config/rocknix ] || _chai_os_release_has rocknix ||
		[ -f /etc/jelos-release ] || [ -f /storage/.config/jelos ] || _chai_os_release_has jelos; then
		echo ROCKNIX
	# ArkOS, dArkOS and derivatives: ogage's pause.sh plus the ark user or an
	# ArkOS version file
	elif [ -f /usr/local/bin/pause.sh ] && { [ -d /home/ark ] || [ -f /etc/arkos_version ] ||
		[ -f /etc/darkos_version ] || _chai_os_release_has arkos; }; then
		echo ArkOS
	# knulli.version is Scarab onwards; older releases are batocera-* based and
	# only identify as Knulli through the board file or os-release
	elif [ -f /usr/share/knulli/knulli.version ] || [ -f /etc/knulli.version ] ||
		[ -f /boot/boot/knulli.board ] || [ -f /boot/knulli.board ] || _chai_os_release_has knulli; then
		echo knulli
	# TrimUI stock and CrossMix. Last, because Spruce and NextUI run on top of
	# TrimUI's stock system and have the same files
	elif [ -d /usr/trimui/bin ] || [ -f /mnt/SDCARD/System/usr/trimui/crossmix-version.txt ]; then
		echo TrimUI
	else
		echo default
	fi
}

if command -v chai >/dev/null 2>&1; then
	CHAI_RETROFIT_PROFILE="native"
else
	CHAI_RETROFIT_PROFILE="$(_chai_detect_profile)"

	sh "${CHAI_RETRO_DIR}/${CHAI_RETROFIT_PROFILE}/setup.sh" setup
	PATH="${CHAI_RETRO_DIR}/bin:${PATH}"
fi

chai_retrofit_teardown() {
	[ "$CHAI_RETROFIT_PROFILE" = "native" ] && return 0
	sh "${CHAI_RETRO_DIR}/${CHAI_RETROFIT_PROFILE}/setup.sh" teardown
}

unset -f _chai_detect_profile _chai_os_release_has

echo "CHAI: using ${CHAI_RETROFIT_PROFILE} ($(command -v chai))"

export PATH
export CHAI_RETROFIT_PROFILE
