#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/emu/lib/ppsspp_functions.sh

# The pair the launcher loads: shared on h700 boards, the parent's on a variant.
suffix="$(get_ppsspp_config_suffix)"
LIVE_PPSSPP_CONFIG="$PPSSPP_LIVE_SYSTEM_DIR/ppsspp-$suffix.ini"
LIVE_PPSSPP_CONTROLS="$PPSSPP_LIVE_SYSTEM_DIR/controls-$suffix.ini"
DEFAULT_PPSSPP_CONFIG="$PPSSPP_DEFAULT_CONFIG_DIR/SYSTEM/ppsspp-$suffix.ini"
DEFAULT_PPSSPP_CONTROLS="$PPSSPP_DEFAULT_CONFIG_DIR/SYSTEM/controls-$suffix.ini"

log_message "Resetting PPSSPP config to default."
mkdir -p "${LIVE_PPSSPP_CONFIG%/*}"
[ -e "$DEFAULT_PPSSPP_CONFIG" ] && cp -f "$DEFAULT_PPSSPP_CONFIG" "$LIVE_PPSSPP_CONFIG"
[ -e "$DEFAULT_PPSSPP_CONFIG" ] || log_message "Reset PPSSPP config: $DEFAULT_PPSSPP_CONFIG does not exist, nothing restored"
[ -e "$DEFAULT_PPSSPP_CONTROLS" ] && cp -f "$DEFAULT_PPSSPP_CONTROLS" "$LIVE_PPSSPP_CONTROLS"
[ -e "$DEFAULT_PPSSPP_CONTROLS" ] || log_message "Reset PPSSPP config: $DEFAULT_PPSSPP_CONTROLS does not exist, controls not restored"
