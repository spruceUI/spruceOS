#!/bin/sh

# Requires:
#   EMU_JSON_PATH
#   get_config_value
#   flag_check
#   flag_add
#   log_message
#   check_and_connect_wifi
#   wifi_request
#   start_syncthing_process
#
# External binaries:
#   /mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh
#   /mnt/SDCARD/spruce/scripts/networkservices.sh
#
# Provides:
#   handle_network_services

CHEEVOS_CACHE_JSON=/mnt/SDCARD/Saves/pyui-cheevos-cache.json

cache_cheevos_at_launch() {
	[ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" = "True" ] || return 0
	[ "$disable_wifi_in_game" = "True" ] || return 0
	[ -s "$CHEEVOS_CACHE_JSON" ] && jq -e --arg p "$PYUI_ROM_PATH" 'any(.[]; .rom_file_path == $p)' "$CHEEVOS_CACHE_JSON" >/dev/null 2>&1 && return 0

	network_is_connected true || check_and_connect_wifi || return 0

	start_pyui_message_writer 1
	display_image_and_text "/mnt/SDCARD/spruce/imgs/signal.png" 35 20 "Caching achievements..." 75
	out="$(/mnt/SDCARD/spruce/scripts/raproxyCacheRom.sh "$ROM_FILE")"
	rc=$?
	stop_pyui_message_writer
	[ "$rc" = "0" ] || return 0

	game_id="$(printf '%s' "$out" | tail -n 1 | jq -r '.game_id // null' 2>/dev/null)"
	[ -s "$CHEEVOS_CACHE_JSON" ] || echo "[]" > "$CHEEVOS_CACHE_JSON"
	tmpfile="$(mktemp)"
	jq --arg p "$PYUI_ROM_PATH" --arg s "$EMU_NAME" --arg n "${GAME%.*}" --argjson id "${game_id:-null}" '
		map(select(.rom_file_path != $p and ($id == null or .game_id != $id))) +
		[{rom_file_path: $p, game_system_name: $s, display_name: $n, game_id: $id}]
		' "$CHEEVOS_CACHE_JSON" > "$tmpfile" && mv "$tmpfile" "$CHEEVOS_CACHE_JSON"
	log_message "Cached achievements for $GAME at launch"
}

reconcile_cheevos_after_game() {
	[ "$cheevos_wanted" = true ] || return 0
	[ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" = "True" ] || return 0
	. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh
	raproxy_reconcile "$PYUI_ROM_PATH" "$EMU_NAME" "${GAME%.*}" >/dev/null 2>&1
}

handle_network_services() {
	if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
		log_message "network_functions.sh: WiFi is off, don't try to connect."
		return 0
	fi

	wifi_needed=false
	syncthing_enabled=false
	wifi_connected=false
	disable_wifi_in_game="$(get_config_value '.menuOptions."Battery Settings".disableWifiInGame.selected' "False")"
	disable_net_serv_in_game="$(get_config_value '.menuOptions."Battery Settings".disableNetworkServicesInGame.selected' "False")"
	syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"

	##### RAC Check #####
	# Runs before prepare_ra_config applies the spruce setting, so read that setting;
	# Manual leaves RetroArch's own per-platform cfg in charge
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	case "$rac_mode" in
		Softcore|Hardcore) cheevos_wanted=true ;;
		Disabled)          cheevos_wanted=false ;;
		*)
			cheevos_wanted=false
			grep -q 'cheevos_enable = "true"' "/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg" 2>/dev/null && cheevos_wanted=true
			;;
	esac
	if [ "$disable_wifi_in_game" = "False" ] && [ "$cheevos_wanted" = true ]; then
		log_message "Retro Achievements enabled, WiFi connection needed"
		wifi_needed=true
	fi

	##### Syncthing Sync Check, perform only once per session #####
	if [ "$syncthing_enabled" = "True" ] && ! flag_check "syncthing_startup_synced"; then
		log_message "Syncthing is enabled, WiFi connection needed"
		wifi_needed=true
		syncthing_enabled=true
	fi

	# Connect to WiFi if needed for any service
	if $wifi_needed; then
		if check_and_connect_wifi; then
			wifi_connected=true
		fi
	fi

	# Handle Syncthing sync if enabled
	if [ "$syncthing_enabled" = "True" ] && $wifi_connected; then
		start_syncthing_process
		/mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh --startup
		flag_add "syncthing_startup_synced" --tmp

	fi

	[ "$cheevos_wanted" = true ] && cache_cheevos_at_launch

	# Handle network service disabling
	if [ "$disable_wifi_in_game" = "True" ] || [ "$disable_net_serv_in_game" = "True" ]; then
		/mnt/SDCARD/spruce/scripts/networkservices.sh off

		if [ "$disable_wifi_in_game" = "True" ]; then
			# Off without changing the setting; the apply at game exit brings it back
			wifi_request suspend
		fi
	fi
}