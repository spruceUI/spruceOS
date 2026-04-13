#!/bin/sh

# Requires:
#   EMU_JSON_PATH
#   get_config_value
#   flag_check
#   flag_add
#   log_message
#   check_and_connect_wifi
#   start_syncthing_process
#
# External binaries:
#   ifconfig
#   killall
#   /mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh
#   /mnt/SDCARD/spruce/scripts/networkservices.sh
#
# Provides:
#   handle_network_services

handle_network_services() {

	# If WiFi is disabled at the system level, skip all network handling
	if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
		log_message "WiFi is disabled, skipping network services"
		return
	fi

	wifi_needed=false
	syncthing_sync_needed=false
	wifi_connected=false
	disable_wifi_in_game="$(get_config_value '.menuOptions."Battery Settings".disableWifiInGame.selected' "False")"
	disable_net_serv_in_game="$(get_config_value '.menuOptions."Battery Settings".disableNetworkServicesInGame.selected' "False")"
	syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"
	sync_before_launch_enabled="$(get_config_value '.menuOptions."Network Settings".syncBeforeLaunch.selected' "True")"

	##### RAC Check #####
	if [ "$disable_wifi_in_game" = "False" ] && grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Achievements enabled, WiFi connection needed"
		wifi_needed=true
	fi

	##### Syncthing Sync Check, perform only once per session #####
	if [ "$syncthing_enabled" = "True" ] && [ "$sync_before_launch_enabled" = "True" ] && ! flag_check "syncthing_startup_synced"; then
		log_message "Syncthing is enabled, WiFi connection needed"
		wifi_needed=true
		syncthing_sync_needed=true
	fi

	# Connect to WiFi if needed for any service
	if $wifi_needed; then
		if check_and_connect_wifi; then
			wifi_connected=true
		fi
	fi

	# Handle Syncthing sync if needed and connected
	if $syncthing_sync_needed && $wifi_connected; then
		start_syncthing_process
		/mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh --startup
		flag_add "syncthing_startup_synced" --tmp
	fi

	# Handle network service disabling
	if [ "$disable_wifi_in_game" = "True" ] || [ "$disable_net_serv_in_game" = "True" ]; then
		/mnt/SDCARD/spruce/scripts/networkservices.sh off
		
		if [ "$disable_wifi_in_game" = "True" ]; then
			if network_is_connected; then
				ifconfig wlan0 down &
			fi
			killall wpa_supplicant
			killall udhcpc
		fi
	fi
}