#!/bin/sh
# BaseOS update for the Anbernic XX line, called by firmwareUpdate.sh.
#
# BaseOS 1.3.0 and newer update themselves from a .bosupd file dropped at the
# root of the frontend card: it applies the update at the next boot and removes
# the file afterwards. So all this does is work out which file this model needs,
# fetch it from the BaseOS releases, check it, and offer a reboot.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"
SD_ROOT="/mnt/SDCARD"
API="https://api.github.com/repos/pvaibhav/BaseOS/releases/latest"
MANUAL_HELP="Please visit github.com/pvaibhav/BaseOS to manually download the proper version for your device."

baseos_field() {
    sed -n "s/^$1=//p" /etc/baseos-release 2>/dev/null | tr -d '"'
}

# 1.2.3 -> 1002003, for a plain numeric comparison. Prints nothing if the
# version is not three numbers, and every caller treats that as "no opinion".
version_num() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    printf '%s' "$1" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}'
}

bail() {
    log_and_display_message "$1"
    sleep 6
    exit 1
}

# No network is the normal case on a model with no built-in radio, so say what
# to do about it rather than just refusing.
dongle_bail() {
    bail "This device needs a USB WiFi dongle to download updates. Plug one in and enable WiFi, or update BaseOS by hand from:\ngithub.com/pvaibhav/BaseOS\n\nPress A to close."
}

INSTALLED="$(baseos_field BASEOS_VERSION)"
TARGET="$(baseos_field BASEOS_TARGET)"
[ -n "$TARGET" ] || bail "Could not tell which BaseOS build this device runs, so there is nothing safe to download.\n\n$MANUAL_HELP"

log_message "baseosUpdate.sh: installed $INSTALLED, target $TARGET, spruce wants ${TARGET_BASEOS_VERSION:-unset}"

log_and_display_message "BaseOS $INSTALLED is installed. Checking for a newer one. Press A to continue."
acknowledge

if ! device_wifi_is_available; then
    dongle_bail 
elif [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" != "1" ]; then
    bail "WiFi is off, so the update cannot be downloaded. Please enable WiFi from spruce settings and try again."
fi
if ! curl -sf -m 20 -o /tmp/baseos_release.json "$API"; then
    bail "Could not reach GitHub to look for a BaseOS update. Please try again later."
fi

LATEST="$(jq -r '.tag_name // empty' /tmp/baseos_release.json | sed 's/^v//')"
ASSET_NAME="$(jq -r --arg t "baseos-${TARGET}-" '.assets[]? | select(.name | startswith($t) and endswith(".bosupd")) | .name' /tmp/baseos_release.json | head -n 1)"
ASSET_URL="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .browser_download_url' /tmp/baseos_release.json | head -n 1)"
ASSET_SIZE="$(jq -r --arg n "$ASSET_NAME" '.assets[]? | select(.name == $n) | .size' /tmp/baseos_release.json | head -n 1)"
SUMS_URL="$(jq -r '.assets[]? | select(.name == "SHA256SUMS") | .browser_download_url' /tmp/baseos_release.json | head -n 1)"

if [ -z "$ASSET_NAME" ] || [ -z "$ASSET_URL" ]; then
    bail "BaseOS ${LATEST:-latest} has no update file for this model ($TARGET), so it has to be installed by hand.\n\n$MANUAL_HELP"
fi

# An update file only applies on top of a BaseOS new enough to look for one.
if [ -n "$INSTALLED" ]; then
    _have="$(version_num "$INSTALLED")"
    _latest="$(version_num "$LATEST")"
    if [ -n "$_have" ] && [ -n "$_latest" ] && [ "$_have" -ge "$_latest" ] 2>/dev/null; then
        log_and_display_message "Your installed BaseOS $INSTALLED is already the version that spruceUI expects. Press A to close."
        acknowledge
        exit 0
    fi
fi

FREE_MB="$(df -m "$SD_ROOT" | awk 'END {print $4}')"
NEED_MB=$(( (${ASSET_SIZE:-0} / 1048576) + 50 ))
if [ "${FREE_MB:-0}" -lt "$NEED_MB" ]; then
    bail "Not enough free space for the BaseOS update: ${NEED_MB} MiB needed, ${FREE_MB} MiB free."
fi

if [ "$(device_get_battery_percent)" -lt 15 ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
    bail "Please charge your device to at least 15%, or plug it in, then try again."
fi

log_and_display_message "BaseOS $LATEST is available (you have $INSTALLED).\n\nIt downloads now and installs on the next start. Press A to continue, B to cancel."
confirm || { log_message "baseosUpdate.sh: user cancelled"; exit 0; }

if ! download_and_display_progress "$ASSET_URL" "$SD_ROOT/$ASSET_NAME" "$ASSET_NAME" "$ASSET_SIZE"; then
    rm -f "$SD_ROOT/$ASSET_NAME"
    bail "The BaseOS update could not be downloaded. Please try again later."
fi

# A truncated or corrupt update file is worse than none: BaseOS would try to
# apply it at boot. Check it against the release's own SHA256SUMS, and only
# skip the check if that file could not be fetched.
if [ -n "$SUMS_URL" ] && curl -sf -m 20 -o /tmp/baseos_sums "$SUMS_URL"; then
    WANT="$(awk -v n="$ASSET_NAME" '$2 == n || $2 == "*"n {print $1}' /tmp/baseos_sums | head -n 1)"
    GOT="$(sha256sum "$SD_ROOT/$ASSET_NAME" | cut -d' ' -f1)"
    if [ -n "$WANT" ] && [ "$WANT" != "$GOT" ]; then
        rm -f "$SD_ROOT/$ASSET_NAME"
        bail "The downloaded BaseOS update was damaged in transit and has been deleted. Please try again."
    fi
    log_message "baseosUpdate.sh: checksum ok for $ASSET_NAME"
else
    log_message "baseosUpdate.sh: WARNING could not fetch SHA256SUMS, skipping the checksum check"
fi

sync

log_and_display_message "BaseOS $LATEST is ready to install. Your device will now reboot into the update procedure, and then power itself off once finished."
sleep 8
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot
