#!/bin/sh
# oakMOSS update for the MagicX Zero 28, Zero 40 and XU20, called by firmwareUpdate.sh.
#
# oakMOSS installs an oakmoss-<board>-<version>.omupd from the root of this card
# into its second slot at the next boot, and falls back to the old slot if the
# new one does not start. So this fetches the file for this board, checks it
# against the release's SHA256SUMS and reboots.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SD_ROOT="/mnt/SDCARD"
API="https://api.github.com/repos/spruceUI/oakMOSS/releases/latest"
MANUAL_HELP="Please visit github.com/spruceUI/oakMOSS to download the image for your device."
BOARD="$(cat /usr/magicx/device 2>/dev/null)"

bail() {
    log_and_display_message "$1"
    sleep 6
    exit 1
}

INSTALLED="$(oakmoss_installed_version)"
log_message "oakmossUpdate.sh: board $BOARD, installed ${INSTALLED:-unknown}"

if ! oakmoss_can_update; then
    bail "This oakMOSS card cannot update itself yet. Flash the latest oakMOSS image once, and later versions will install from here.\n\n$MANUAL_HELP"
fi

log_and_display_message "oakMOSS $INSTALLED is installed. Checking for a newer one. Press A to continue."
acknowledge

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != "1" ]; then
    bail "WiFi is off, so the update cannot be downloaded. Please enable WiFi from spruce settings and try again."
fi
if ! curl -sf -m 20 -o /tmp/oakmoss_release.json "$API"; then
    bail "Could not reach GitHub to look for an oakMOSS update. Please try again later."
fi

LATEST="$(jq -r '.tag_name // empty' /tmp/oakmoss_release.json | sed 's/^[vV]//')"
ASSET_NAME="$(jq -r --arg t "oakmoss-${BOARD}-" '.assets[]? | select(.name | startswith($t) and endswith(".omupd")) | .name' /tmp/oakmoss_release.json | head -n 1)"
ASSET_URL="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .browser_download_url' /tmp/oakmoss_release.json | head -n 1)"
ASSET_SIZE="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .size' /tmp/oakmoss_release.json | head -n 1)"
SUMS_URL="$(jq -r '.assets[]? | select(.name == "SHA256SUMS") | .browser_download_url' /tmp/oakmoss_release.json | head -n 1)"

if ! oakmoss_version_older_than "$INSTALLED" "$LATEST"; then
    log_and_display_message "Your installed oakMOSS $INSTALLED is already the latest release. Press A to close."
    acknowledge
    exit 0
fi

if [ -z "$ASSET_NAME" ] || [ -z "$ASSET_URL" ]; then
    bail "oakMOSS $LATEST has no update file for this device ($BOARD), so it has to be installed by hand.\n\n$MANUAL_HELP"
fi

FREE_MB="$(df -m "$SD_ROOT" | awk 'END {print $4}')"
NEED_MB=$(( (${ASSET_SIZE:-0} / 1048576) + 50 ))
if [ "${FREE_MB:-0}" -lt "$NEED_MB" ]; then
    bail "Not enough free space on the spruce card for the oakMOSS update: ${NEED_MB} MiB needed, ${FREE_MB} MiB free."
fi

if [ "$(device_get_battery_percent)" -lt 15 ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
    bail "Please charge your device to at least 15%, or plug it in, then try again."
fi

log_and_display_message "oakMOSS $LATEST is available (you have $INSTALLED).\n\nPress A to download and install it now, or B to cancel."
confirm || { log_message "oakmossUpdate.sh: user cancelled"; exit 0; }

# oakMOSS installs any .omupd it finds at boot, so the file only gets its real
# name once it is complete and matches the release's sums.
PART="$SD_ROOT/$ASSET_NAME.part"
rm -f "$SD_ROOT"/oakmoss-*.omupd.part
if ! download_and_display_progress "$ASSET_URL" "$PART" "$ASSET_NAME" "$ASSET_SIZE"; then
    rm -f "$PART"
    bail "The oakMOSS update could not be downloaded. Please try again later."
fi

if [ -n "$SUMS_URL" ] && curl -sf -m 20 -o /tmp/oakmoss_sums "$SUMS_URL"; then
    WANT="$(awk -v n="$ASSET_NAME" '$2 == n || $2 == "*"n {print $1}' /tmp/oakmoss_sums | head -n 1)"
    GOT="$(sha256sum "$PART" | cut -d' ' -f1)"
    if [ -n "$WANT" ] && [ "$WANT" != "$GOT" ]; then
        rm -f "$PART"
        bail "The downloaded oakMOSS update was damaged in transit and has been deleted. Please try again."
    fi
    log_message "oakmossUpdate.sh: checksum ok for $ASSET_NAME"
else
    log_message "oakmossUpdate.sh: WARNING could not fetch SHA256SUMS, skipping the checksum check"
fi

rm -f "$SD_ROOT"/oakmoss-*.omupd
mv "$PART" "$SD_ROOT/$ASSET_NAME"
sync

log_and_display_message "oakMOSS $LATEST is ready to install. Your device will now reboot and install it, which takes about a minute. Do not power off the device."
sleep 8
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
