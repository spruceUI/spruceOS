#!/bin/sh
# oakMOSS update for the MagicX Mini Zero 28, Zero 40 and XU20 V32, called by firmwareUpdate.sh.
#
# Every oakMOSS release ships an oakmoss-<board>-<tag>.omupd beside its images. The base installs
# it itself: at boot, runmagicx.sh hands every oakmoss-<board>-*.omupd at the root of a card to
# oakmoss-update.sh, which writes the other slot and boots it (oakMOSS docs/updates.md). So this
# only fetches the file, checks it against the release's SHA256SUMS, puts it in place and reboots.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

SD_ROOT="/mnt/SDCARD"
API="https://api.github.com/repos/spruceUI/oakMOSS/releases/latest"
MANUAL_HELP="Please visit github.com/spruceUI/oakMOSS to download the image for your device and write it to the system card."
BOARD="$(magicx_model)"

bail() {
    log_and_display_message "$1"
    sleep 6
    exit 1
}

INSTALLED="$(oakmoss_installed_version)"
log_message "oakmossUpdate.sh: $BOARD, installed ${INSTALLED:-unknown}"

if ! oakmoss_can_update; then
    bail "This system card has no oakMOSS update support (oakMOSS ${INSTALLED:-unknown}).\n\n$MANUAL_HELP"
fi

log_and_display_message "oakMOSS $INSTALLED is installed. Checking for a newer one. Press A to continue."
acknowledge

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != "1" ]; then
    bail "WiFi is off, so the update cannot be downloaded. Please enable WiFi from spruce settings and try again."
fi
if ! curl -sf -m 20 -o /tmp/oakmoss_release.json "$API"; then
    bail "Could not reach GitHub to look for an oakMOSS update. Please try again later."
fi

LATEST="$(jq -r '.tag_name // empty' /tmp/oakmoss_release.json)"
ASSET_NAME="$(jq -r --arg n "oakmoss-${BOARD}-${LATEST}.omupd" '.assets[]? | select(.name == $n) | .name' /tmp/oakmoss_release.json | head -n 1)"
ASSET_URL="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .browser_download_url' /tmp/oakmoss_release.json | head -n 1)"
ASSET_SIZE="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .size' /tmp/oakmoss_release.json | head -n 1)"
SUMS_URL="$(jq -r '.assets[]? | select(.name == "SHA256SUMS") | .browser_download_url' /tmp/oakmoss_release.json | head -n 1)"

if [ -z "$LATEST" ] || ! oakmoss_version_older "$INSTALLED" "$LATEST"; then
    hide_fw_app
    log_and_display_message "Your oakMOSS $INSTALLED is already the latest release. Press A to close."
    acknowledge
    exit 0
fi
if [ -z "$ASSET_NAME" ] || [ -z "$ASSET_URL" ] || [ -z "$SUMS_URL" ]; then
    bail "oakMOSS $LATEST has no update file for this device ($BOARD), so it has to be installed by hand.\n\n$MANUAL_HELP"
fi

FREE_MB="$(df -m "$SD_ROOT" | awk 'END {print $4}')"
NEED_MB=$(( (${ASSET_SIZE:-0} / 1048576) + 50 ))
if [ "${FREE_MB:-0}" -lt "$NEED_MB" ]; then
    bail "Not enough free space on the spruce card for the oakMOSS update: ${NEED_MB} MiB needed, ${FREE_MB} MiB free."
fi

# The installer waits, writing nothing, below 30% without a charger.
if [ "$(device_get_battery_percent)" -lt 30 ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
    bail "Please charge your device to at least 30%, or plug it in, then try again."
fi

log_and_display_message "oakMOSS $LATEST is available (you have $INSTALLED).\n\nPress A to download it and restart to install it, or B to cancel."
confirm || { log_message "oakmossUpdate.sh: user cancelled"; exit 0; }

# Downloaded under another name: at boot only a whole, checked file may match oakmoss-<board>-*.omupd.
PART="$SD_ROOT/$ASSET_NAME.part"
if ! download_and_display_progress "$ASSET_URL" "$PART" "$ASSET_NAME" "$ASSET_SIZE"; then
    rm -f "$PART"
    bail "The oakMOSS update could not be downloaded. Please try again later."
fi

if ! curl -sf -m 20 -o /tmp/oakmoss_sums "$SUMS_URL"; then
    rm -f "$PART"
    bail "Could not download the release's checksums, so the update was not installed. Please try again later."
fi
WANT="$(awk -v n="$ASSET_NAME" '$2 == n || $2 == "*"n {print $1}' /tmp/oakmoss_sums | head -n 1)"
GOT="$(sha256sum "$PART" | cut -d' ' -f1)"
if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then
    rm -f "$PART"
    bail "The downloaded oakMOSS update did not match the release's checksum and has been deleted. Please try again."
fi
log_message "oakmossUpdate.sh: checksum ok for $ASSET_NAME"
mv -f "$PART" "$SD_ROOT/$ASSET_NAME"
sync

log_and_display_message "oakMOSS $LATEST is ready. Your device will now restart and install it: do not power it off while it shows Updating."
sleep 5
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
