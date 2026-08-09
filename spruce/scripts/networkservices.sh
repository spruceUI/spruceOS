#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/darkhttpdFunctions.sh

SFTP_SERVICE_NAME=$(get_sftp_service_name)
SSH_SERVICE_NAME=$(get_ssh_service_name)

samba_enabled="$(get_config_value '.menuOptions."Network Settings".enableSamba.selected' "False")"
ssh_enabled="$(get_config_value '.menuOptions."Network Settings".enableSSH.selected' "False")"
sftpgo_enabled="$(get_config_value '.menuOptions."Network Settings".enableSFTPGo.selected' "False")"
syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"

# Directory, not a file: mkdir is atomic, so two near-simultaneous launches
# cannot both decide they hold the lock.
CONNECT_LOCK="/tmp/networkservices_connecting"
CONNECT_LOCK_PID="$CONNECT_LOCK/pid"

# Poll fast at first so services come up promptly on a normal boot, then back
# off. We still wait indefinitely -- services must start whenever the network
# eventually appears -- but network_is_connected forks ifconfig+grep on every
# pass, and enable_wifi launches a fresh copy of this script on every return to
# the menu. Without the lock and the backoff, a device that never connects ends
# up running one busy loop per game launch, which is enough to visibly slow
# emulation on a two-core device.
CONNECT_FAST_POLLS=60		# 60 x 0.5s = first 30 seconds
CONNECT_FAST_INTERVAL=0.5
CONNECT_SLOW_INTERVAL=10

# True if $1 looks like a live networkservices.sh, guarding against PID reuse.
# grep reads /proc/<pid>/cmdline directly; the NUL separators do not matter
# because the name we want sits inside a single argument.
lock_holder_is_alive() {
	[ -n "$1" ] && [ -d "/proc/$1" ] || return 1
	grep -q "networkservices.sh" "/proc/$1/cmdline" 2>/dev/null
}

connect_services() {

	# Only one instance should ever be waiting for a connection.
	if ! mkdir "$CONNECT_LOCK" 2>/dev/null; then
		if lock_holder_is_alive "$(cat "$CONNECT_LOCK_PID" 2>/dev/null)"; then
			log_message "Network services: another instance is already waiting for a connection, exiting."
			return 0
		fi
		# Holder died without cleaning up (e.g. kill -9). Reclaim the lock.
		log_message "Network services: clearing stale connect lock."
		rm -rf "$CONNECT_LOCK"
		mkdir "$CONNECT_LOCK" 2>/dev/null || return 0
	fi
	echo "$$" >"$CONNECT_LOCK_PID"
	trap 'rm -rf "$CONNECT_LOCK"' EXIT INT TERM

	polls=0
	while ! network_is_connected true; do
		if [ "$polls" -lt "$CONNECT_FAST_POLLS" ]; then
			sleep "$CONNECT_FAST_INTERVAL"
			polls=$((polls + 1))
			if [ "$polls" -eq "$CONNECT_FAST_POLLS" ]; then
				log_message "Network services: still no connection, backing off to ${CONNECT_SLOW_INTERVAL}s checks."
			fi
		else
			sleep "$CONNECT_SLOW_INTERVAL"
		fi
	done
	rm -rf "$CONNECT_LOCK"
	trap - EXIT INT TERM

	# Samba check
	if [ "$samba_enabled" = "True" ]; then
		if ! pgrep "smbd" >/dev/null; then
			log_message "Network services: Samba detected not running, starting..."
			start_samba_process
		fi
	else
		stop_samba_process
	fi

	# SSH check
	if [ "$ssh_enabled" = "True" ]; then
		if ! pgrep "$SSH_SERVICE_NAME" >/dev/null; then
			log_message "Network services: $SSH_SERVICE_NAME detected not running, starting..."
			start_ssh_process
		fi
	else
		stop_ssh_process
	fi

	# SFTPGo check
	if [ "$sftpgo_enabled" = "True" ]; then
		if ! pgrep "$SFTP_SERVICE_NAME" >/dev/null; then
			log_message "Network services: SFTPGo detected not running, starting..."
			start_sftpgo_process
		fi
	else
		stop_sftpgo_process
	fi

	# Syncthing check
	if [ "$syncthing_enabled" = "True" ]; then
		if ! pgrep "syncthing" >/dev/null; then
			log_message "Network services: Syncthing detected not running, starting..."
			start_syncthing_process
		fi
	else
		stop_syncthing_process
	fi

	# Start Network Services Landing page
	start_darkhttpd_process

}

disconnect_services() {
	# Stop an instance that is still waiting for a connection, otherwise it
	# keeps polling even though services are being torn down. lock_holder_is_alive
	# checks the cmdline too, so a recycled PID is never signalled.
	if [ -d "$CONNECT_LOCK" ]; then
		lock_pid="$(cat "$CONNECT_LOCK_PID" 2>/dev/null)"
		if lock_holder_is_alive "$lock_pid"; then
			log_message "Network services: stopping instance still waiting for a connection (pid $lock_pid)"
			kill "$lock_pid" 2>/dev/null
		fi
		rm -rf "$CONNECT_LOCK"
	fi

	log_message "Network services: Stopping all network services..."
	for service in "$SFTP_SERVICE_NAME" "$SSH_SERVICE_NAME" "smbd" "syncthing" "darkhttpd"; do
		if pgrep "$service" >/dev/null; then
			case "$service" in
			"$SFTP_SERVICE_NAME") stop_sftpgo_process ;;
			"$SSH_SERVICE_NAME") stop_ssh_process ;;
			"smbd") stop_samba_process ;;
			"syncthing") stop_syncthing_process ;;
			"darkhttpd") stop_darkhttpd_process ;;
			esac
		fi
	done

}

if [ "$1" = "off" ]; then
	disconnect_services
else
	connect_services
fi
