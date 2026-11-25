#!/bin/sh
# CHAI retrofit: ArkOS family (ArkOS, dArkOS)
#
# Ports run as the ark user with passwordless sudo, so anything that needs
# root goes through "sudo -n". Anything not overridden here uses the default
# profile (sysfs backlight and battery).

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# Runs a command as root: directly if already root, otherwise with sudo -n
chai_ark_root() {
	if [ "$(id -u)" = 0 ]; then
		"$@"
	else
		sudo -n "$@"
	fi
}

# The default profile's sysfs write, rerun as root when ark can't write the
# backlight
chai_set_brightness() {
	if [ "$(id -u)" != 0 ] && chai_bl_detect && [ -n "$BL_DIR" ] && [ ! -w "$BL_DIR/brightness" ]; then
		sudo -n sh "$0" set-brightness "$@"
		return
	fi
	chai_default_set_brightness "$@"
}

# auto_suspend.py suspends after its idle timeout only while
# /usr/local/bin/processcheck.sh prints "Nothing" (it prints "Running" for
# Kodi and ffplay). A copy that always prints "Running" is bind-mounted over
# it. A bind mount is gone after a reboot, so a crash can't leave it.
# The power button (ogage -> pause.sh) is left alone. ArkOS devices have no lid.
ARK_PROCESS_CHECK=/usr/local/bin/processcheck.sh
ARK_PROCESS_CHECK_COPY="$CHAI_RUN_DIR/processcheck.sh"

chai_set_idle_suppression() {
	[ -f "$ARK_PROCESS_CHECK" ] || return 0
	case "$1" in
		1)
			chai_idle_mark || return 0
			grep -q " $ARK_PROCESS_CHECK " /proc/mounts && return 0
			printf '#!/bin/sh\n# CHAI idle suppression is on\nprintf Running\n' >"$ARK_PROCESS_CHECK_COPY"
			chmod +x "$ARK_PROCESS_CHECK_COPY"
			chai_ark_root mount --bind "$ARK_PROCESS_CHECK_COPY" "$ARK_PROCESS_CHECK"
			;;
		0)
			chai_idle_unmark || return 0
			while grep -q " $ARK_PROCESS_CHECK " /proc/mounts; do
				chai_ark_root umount -l "$ARK_PROCESS_CHECK" || break
			done
			rm -f "$ARK_PROCESS_CHECK_COPY"
			;;
	esac
	return 0
}

# "Switch to SD2 for Roms" points ES's systems at /roms2
chai_get_path() {
	case "$1" in
		userdata) echo /home/ark ;;
		roms)
			if grep -q '<path>/roms2/' /etc/emulationstation/es_systems.cfg 2>/dev/null; then
				echo /roms2
			else
				echo /roms
			fi
			;;
		*) chai_default_get_path "$@" ;;
	esac
}

chai_main "$@"
