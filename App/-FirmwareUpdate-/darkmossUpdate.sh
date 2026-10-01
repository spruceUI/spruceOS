#!/bin/sh
# dArkMoss update for the RGB30, RGB20SX and Miniloong, called by firmwareUpdate.sh.
#
# Every dArkMoss release ships a dArkMoss_<UNIT>_<tag>.dmupd beside its image:
# the boot partition plus the rootfs files the dArkMoss build authored, with its
# own apply.sh inside. Nothing on TF1 knows how to update itself, but spruce
# runs as root on a writable rootfs here, so this fetches the payload, checks
# it against the release's SHA256SUMS, runs its applier, and reboots.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SD_ROOT="/mnt/SDCARD"
API="https://api.github.com/repos/spruceUI/dArkMoss/releases/latest"
MANUAL_HELP="Please visit github.com/spruceUI/dArkMoss to manually download the proper image for your device."
# The image's unit, not $PLATFORM: the RGB20SX runs the RGB30 image.
UNIT="$(sed -n 's/^SPRUCE_PLATFORM="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)"
UNIT="$(printf '%s' "${UNIT:-$PLATFORM}" | tr 'a-z' 'A-Z')"

bail() {
    log_and_display_message "$1"
    sleep 6
    exit 1
}

INSTALLED="$(darkmoss_installed_version)"
log_message "darkmossUpdate.sh: installed ${INSTALLED:-unknown}, spruce wants ${TARGET_DARKMOSS_VERSION:-unset}"

log_and_display_message "dArkMoss ${INSTALLED:-(unknown version)} is installed. Checking for a newer one. Press A to continue."
acknowledge

if [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != "1" ]; then
    bail "WiFi is off, so the update cannot be downloaded. Please enable WiFi from spruce settings and try again."
fi
if ! curl -sf -m 20 -o /tmp/darkmoss_release.json "$API"; then
    bail "Could not reach GitHub to look for a dArkMoss update. Please try again later."
fi

LATEST="$(jq -r '.tag_name // empty' /tmp/darkmoss_release.json | sed 's/^[vV]//')"
ASSET_NAME="$(jq -r --arg t "dArkMoss_${UNIT}_" '.assets[]? | select(.name | startswith($t) and endswith(".dmupd")) | .name' /tmp/darkmoss_release.json | head -n 1)"
ASSET_URL="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .browser_download_url' /tmp/darkmoss_release.json | head -n 1)"
ASSET_SIZE="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .size' /tmp/darkmoss_release.json | head -n 1)"
SUMS_URL="$(jq -r '.assets[]? | select(.name == "SHA256SUMS") | .browser_download_url' /tmp/darkmoss_release.json | head -n 1)"

if [ -z "$ASSET_NAME" ] || [ -z "$ASSET_URL" ]; then
    bail "dArkMoss ${LATEST:-latest} has no update file for this device ($UNIT), so it has to be installed by hand.\n\n$MANUAL_HELP"
fi

if [ -n "$INSTALLED" ]; then
    _have="$(printf '%s' "$INSTALLED" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')"
    _latest="$(printf '%s' "$LATEST" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')"
    if [ "$_have" -ge "$_latest" ] 2>/dev/null; then
        log_and_display_message "Your installed dArkMoss $INSTALLED is already the latest release. Press A to close."
        acknowledge
        exit 0
    fi
fi

# The payload is downloaded to TF2 and unpacked onto TF1's rootfs.
FREE_MB="$(df -m "$SD_ROOT" | awk 'END {print $4}')"
NEED_MB=$(( (${ASSET_SIZE:-0} / 1048576) + 50 ))
if [ "${FREE_MB:-0}" -lt "$NEED_MB" ]; then
    bail "Not enough free space on the spruce card for the dArkMoss update: ${NEED_MB} MiB needed, ${FREE_MB} MiB free."
fi
ROOT_FREE_MB="$(df -m / | awk 'END {print $4}')"
ROOT_NEED_MB=$(( (${ASSET_SIZE:-0} / 1048576) * 3 + 100 ))
if [ "${ROOT_FREE_MB:-0}" -lt "$ROOT_NEED_MB" ]; then
    bail "Not enough free space on the dArkMoss card to install the update: ${ROOT_NEED_MB} MiB needed, ${ROOT_FREE_MB} MiB free."
fi

if [ "$(device_get_battery_percent)" -lt 15 ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
    bail "Please charge your device to at least 15%, or plug it in, then try again."
fi

log_and_display_message "dArkMoss $LATEST is available (you have ${INSTALLED:-an unknown version}).\n\nPress A to download and install it now, or B to cancel."
confirm || { log_message "darkmossUpdate.sh: user cancelled"; exit 0; }

if ! download_and_display_progress "$ASSET_URL" "$SD_ROOT/$ASSET_NAME" "$ASSET_NAME" "$ASSET_SIZE"; then
    rm -f "$SD_ROOT/$ASSET_NAME"
    bail "The dArkMoss update could not be downloaded. Please try again later."
fi

# The applier checks the archives inside against the manifest, but the manifest
# itself is only trusted because the whole file matches the release's sums.
if [ -n "$SUMS_URL" ] && curl -sf -m 20 -o /tmp/darkmoss_sums "$SUMS_URL"; then
    WANT="$(awk -v n="$ASSET_NAME" '$2 == n || $2 == "*"n {print $1}' /tmp/darkmoss_sums | head -n 1)"
    GOT="$(sha256sum "$SD_ROOT/$ASSET_NAME" | cut -d' ' -f1)"
    if [ -n "$WANT" ] && [ "$WANT" != "$GOT" ]; then
        rm -f "$SD_ROOT/$ASSET_NAME"
        bail "The downloaded dArkMoss update was damaged in transit and has been deleted. Please try again."
    fi
    log_message "darkmossUpdate.sh: checksum ok for $ASSET_NAME"
else
    log_message "darkmossUpdate.sh: WARNING could not fetch SHA256SUMS, skipping the checksum check"
fi

APPLY_DIR="$(mktemp -d /var/tmp/dmupd-apply.XXXXXX)"
if ! tar -xf "$SD_ROOT/$ASSET_NAME" -C "$APPLY_DIR" apply.sh 2>/dev/null; then
    rm -rf "$APPLY_DIR" "$SD_ROOT/$ASSET_NAME"
    bail "The downloaded file is not a dArkMoss update and has been deleted.\n\n$MANUAL_HELP"
fi

log_and_display_message "Installing dArkMoss $LATEST. This takes a minute or two. Do not power off the device."
sh "$APPLY_DIR/apply.sh" "$SD_ROOT/$ASSET_NAME" > "$APPLY_DIR/apply.log" 2>&1
APPLY_RC=$?
while IFS= read -r line; do
    log_message "darkmossUpdate.sh: $line"
done < "$APPLY_DIR/apply.log"
rm -rf "$APPLY_DIR"
rm -f "$SD_ROOT/$ASSET_NAME"
sync

if [ "$APPLY_RC" -ne 0 ]; then
    bail "The dArkMoss update did not complete; spruce.log has the details. If the device no longer boots, reflash the dArkMoss image on TF1. Your spruce card is unaffected."
fi

log_and_display_message "dArkMoss $LATEST is installed. Your device will now reboot."
sleep 5
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
