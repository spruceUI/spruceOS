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

	wifi_needed=false
	syncthing_sync_needed=false
	wifi_connected=false
	wifi_is_on="$(jq -r '.wifi // 0' "$SYSTEM_JSON")"
	disable_wifi_in_game="$(get_config_value '.menuOptions."Battery Settings".disableWifiInGame.selected' "False")"
	disable_net_serv_in_game="$(get_config_value '.menuOptions."Battery Settings".disableNetworkServicesInGame.selected' "False")"
	syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"

	##### RAC Check — only if WiFi is already on #####
	if [ "$wifi_is_on" -ne 0 ] && [ "$disable_wifi_in_game" = "False" ] && grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Achievements enabled, WiFi connection needed"
		wifi_needed=true
	fi

	##### Syncthing Sync Check — syncs even if WiFi is off, once per session #####
	if [ "$syncthing_enabled" = "True" ] && ! flag_check "syncthing_startup_synced"; then
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

	# If WiFi failed and Syncthing was the reason, offer to disable it
	if $syncthing_sync_needed && ! $wifi_connected; then
		log_message "WiFi connection failed, prompting to disable Syncthing"
		start_pyui_message_writer 1
		display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 35 20 \
			"WiFi unavailable.\nPress A to continue,\nB to disable Syncthing." 75
		if confirm; then
			log_message "User chose to continue without Syncthing sync"
		else
			log_message "User chose to disable Syncthing"
			SPRUCE_JSON="/mnt/SDCARD/Saves/spruce/spruce-config.json"
			TMP_JSON="$(mktemp)"
			jq '.menuOptions["Network Settings"].enableSyncthing.selected = "False"' \
				"$SPRUCE_JSON" > "$TMP_JSON" && mv "$TMP_JSON" "$SPRUCE_JSON"
			display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 35 25 \
				"Syncthing disabled." 75
			sleep 2
		fi
		stop_pyui_message_writer
		syncthing_sync_needed=false
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