#!/bin/sh

# Two unrelated cleanups, both of things that will not correct themselves.
#
# Everything in here has to be safe to run more than once, because re-running is
# the normal case rather than an edge case. The updater deletes App/spruceRestore
# (it is in APP_DELETE_LIST in App/-Updater/delete_files.sh) before extracting,
# and .lastUpdate lives inside that folder. Nothing puts it back -- it is
# untracked, so it is not in the archive either. So after an in-device update
# there is no .lastUpdate, the runner falls back to 2.0.0, and every upgrade
# script runs again.
#
#
# 1. Clear the rom list cache written by 4.3.0 - 4.3.2
#
# Those versions decided whether a cached rom listing was still good by checking
# the folder's modification date. That date is not trustworthy: archive tools
# (7-Zip, WinRAR, Windows' built in extract) write the date stored inside the
# archive back onto the folder after extracting into it, so a folder can gain
# games while its date stays put or moves backwards. When that happened the
# cached listing was kept and the new games never appeared, permanently.
#
# 4.3.3 confirms cached listings in the background and corrects them, so a stale
# cache now repairs itself. Clearing it here just means affected users get the
# right list the first time they open a system instead of seeing the old one
# flash up once beforehand.
#
#
# 2. Drop the GBA overlay viewport that only ever fitted a 640x480 screen
#
# Turning on Perfect Overlays used to write aspect_ratio_index = "23" (custom)
# and custom_viewport_height = "427" into the GBA core configs. 427 is not a
# general number: at 640 wide it is GBA's 3:2 to the pixel, so it was only ever
# right on the 640x480 devices the setting was offered on. GB.sh and GBC.sh
# never set either key, so GBA was the odd one out, and the pair is now gone
# from GBA.sh so the setting can be offered on the Brick and BrickPro too.
#
# Removing them from that script is not enough on its own. update_config_file
# only rewrites the keys it is about to write, so a config that already has
# these two keeps them, and applyPerfectOs.sh is guarded by the perfectOverlays
# flag, so a re-apply does not even run for anyone who already had it on. Left
# alone they would sit there permanently, and the only way out would be toggling
# the setting off and on again.
#
# Only the exact values the old script wrote are removed, and only when both are
# present together, since that pair is its signature. Anyone who has set their
# own aspect ratio or viewport height for GBA keeps it. There is deliberately no
# check of the perfectOverlays flag: anyone who turned the setting off already
# had both keys taken out by remove_overlay, which still lists them.

TARGET_VERSION="4.3.3"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

ROM_LIST_CACHE="/mnt/SDCARD/Saves/cache"

if [ -d "$ROM_LIST_CACHE" ]; then
    cached_count=$(find "$ROM_LIST_CACHE" -maxdepth 1 -name '*.json' | wc -l)
    rm -rf "$ROM_LIST_CACHE"
    log_message "Removed rom list cache ($cached_count cached folder listings)"
else
    log_message "No rom list cache present, nothing to clear"
fi

# The two cores GBA.sh applies its cfg to.
GBA_CFG_FILES="/mnt/SDCARD/RetroArch/.retroarch/config/gpSP/GBA.cfg
/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GBA.cfg"

ASPECT_LINE='^aspect_ratio_index[[:space:]]*=[[:space:]]*"23"[[:space:]]*$'
VIEWPORT_LINE='^custom_viewport_height[[:space:]]*=[[:space:]]*"427"[[:space:]]*$'

# Not piped into the loop: that runs it in a subshell, and nothing it does to
# the surrounding shell survives. Neither path contains a space.
for cfg_file in $GBA_CFG_FILES; do
    if [ ! -f "$cfg_file" ]; then
        log_message "GBA overlay viewport: $cfg_file not present, nothing to do"
        continue
    fi

    if ! grep -q "$ASPECT_LINE" "$cfg_file" || ! grep -q "$VIEWPORT_LINE" "$cfg_file"; then
        log_message "GBA overlay viewport: $cfg_file does not carry both keys, leaving it alone"
        continue
    fi

    if sed -e "/$ASPECT_LINE/d" -e "/$VIEWPORT_LINE/d" "$cfg_file" > "$cfg_file.tmp"; then
        mv "$cfg_file.tmp" "$cfg_file"
        log_message "GBA overlay viewport: removed aspect_ratio_index and custom_viewport_height from $cfg_file"
    else
        rm -f "$cfg_file.tmp"
        log_message "GBA overlay viewport: could not rewrite $cfg_file, left unchanged"
    fi
done

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
