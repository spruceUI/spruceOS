#!/bin/sh

# Clock and timezone sync, done by timesync.py once the network is up. Its log
# lines come back as "LOG ..." or "VLOG ..." (verbose).

run_timesync() {
	"$(get_python_path)" /mnt/SDCARD/spruce/scripts/network/timesync.py "$@" 2>&1 |
		while IFS= read -r _line; do
			case "$_line" in
			"VLOG "*) log_message "${_line#VLOG }" -v ;;
			"LOG "*) log_message "${_line#LOG }" ;;
			*) log_message "timesync.py: $_line" ;;
			esac
		done
}

# Pass --again to run even if it already ran this boot.
sync_system_time() {
	run_timesync clock "$@"
}

sync_timezone_from_network() {
	run_timesync timezone "$@"
}
