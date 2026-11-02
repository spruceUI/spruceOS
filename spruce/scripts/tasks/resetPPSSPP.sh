#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LIVE_PPSSPP_CONFIG="$(platform_path "/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/ppsspp-%s.ini")"
LIVE_PPSSPP_CONTROLS="$(platform_path "/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-%s.ini")"
DEFAULT_PPSSPP_CONFIG="$(platform_path "/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/ppsspp-%s.ini")"
DEFAULT_PPSSPP_CONTROLS="$(platform_path "/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/controls-%s.ini")"

log_message "Resetting PPSSPP config to default."
mkdir -p "${LIVE_PPSSPP_CONFIG%/*}"
[ -e "$DEFAULT_PPSSPP_CONFIG" ] && cp -f "$DEFAULT_PPSSPP_CONFIG" "$LIVE_PPSSPP_CONFIG"
[ -e "$DEFAULT_PPSSPP_CONFIG" ] || log_message "Reset PPSSPP config: $DEFAULT_PPSSPP_CONFIG does not exist, nothing restored"
[ -e "$DEFAULT_PPSSPP_CONTROLS" ] && cp -f "$DEFAULT_PPSSPP_CONTROLS" "$LIVE_PPSSPP_CONTROLS"
[ -e "$DEFAULT_PPSSPP_CONTROLS" ] || log_message "Reset PPSSPP config: $DEFAULT_PPSSPP_CONTROLS does not exist, controls not restored"
