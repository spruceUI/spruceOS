#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/update.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"

OTA_URL="https://spruceui.github.io/OTA/spruce"
OTA_URL_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceui.github.io/refs/heads/main/OTA/spruce"
OTA_URL_BACKUP_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceSource/refs/heads/main/OTA/spruce"
TMP_DIR="/mnt/SDCARD/App/-OTA/tmp"

##### FUNCTIONS #####

is_wifi_connected() {
    if ping -c 3 -W 2 spruceui.github.io > /dev/null 2>&1; then
        log_message "GitHub ping successful; device is online."
        return 0
    else
        display_image_and_text "$BAD_IMG" 35 20 "GitHub ping failed; device is offline. Aborting." 75
        return 1
    fi
}

download_release_info() {
    local url="$1"
    local output_file="$2"
    local tmp_dir="$3"
    
    # Try to download the file with certificate verification first
    # (SSL_CERT_FILE points at the bundled CA file). Only a TLS failure
    # falls back to -k, so a working TLS stack is never silently downgraded.
    curl -S -s -f -o "$output_file" "$url" 2>"$tmp_dir/curl_error"
    curl_result=$?

    if [ "$curl_result" -ne 0 ]; then
        case "$curl_result" in
            35|51|58|59|60|77)
                log_message "OTA: TLS verification failed for $url (curl $curl_result: $(cat "$tmp_dir/curl_error")); retrying without certificate verification"
                if ! curl -k -S -s -f -o "$output_file" "$url" 2>"$tmp_dir/curl_error"; then
                    error_msg=$(cat "$tmp_dir/curl_error")
                    log_message "OTA: Failed to download from $url - Error: $error_msg"
                    return 1
                fi
                ;;
            *)
                error_msg=$(cat "$tmp_dir/curl_error")
                log_message "OTA: Failed to download from $url - Error: $error_msg"
                return 1
                ;;
        esac
    fi
    
    # Verify we got valid content
    if ! grep -q "RELEASE_VERSION=" "$output_file"; then
        log_message "OTA: Invalid or empty release info file from $url"
        return 1
    fi
    
    return 0
}

set_target() {
    local version="$1"
    local checksum="$2"
    local link="$3"
    local size="$4"
    local info="$5"
    
    TARGET_VERSION="$version"
    TARGET_CHECKSUM="$checksum"
    TARGET_LINK="$link"
    TARGET_SIZE="$size"
    TARGET_INFO="$info"
}

verify_checksum() {
    local file="$1"
    local expected_checksum="$2"
    local downloaded_checksum

    downloaded_checksum=$(md5sum "$file" | cut -d' ' -f1)

    if [ "$(printf '%s' "$downloaded_checksum")" = "$(printf '%s' "$expected_checksum")" ]; then
        return 0 # Success
    else
        log_message "OTA: Checksum verification failed, received: $downloaded_checksum, expected: $expected_checksum"
        rm -f "$file"
        return 1 # Failure
    fi
}

# Escape a version string for use inside a grep/sed basic regular expression.
# Dots in versions are regex wildcards unless escaped.
escape_re() {
    printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'
}

# Convert "major.minor.patch" (optionally prefixed with "v" and/or suffixed
# with "-<anything>", e.g. "4.4.1-20260826") into a single comparable integer.
# Prints nothing and returns 1 for malformed input.
version_num() {
    local v major minor patch rest
    v="$(printf '%s' "$1" | sed 's/^v//; s/-.*$//')"
    case "$v" in
        ""|*[!0-9.]*|.*|*.) return 1 ;;
    esac
    major="${v%%.*}"
    rest="${v#*.}"
    if [ "$rest" = "$v" ]; then
        minor=0; patch=0
    else
        minor="${rest%%.*}"
        rest="${rest#*.}"
        if [ "$rest" = "$minor" ]; then patch=0; else patch="${rest%%.*}"; fi
    fi
    [ -z "$minor" ] && minor=0
    [ -z "$patch" ] && patch=0
    echo $((major * 1000000 + minor * 1000 + patch))
}

# Queue the traditional complete archive for the current channel.
queue_full_update() {
    if [ "$TARGET_CHANNEL" = "nightly" ]; then
        if [ -z "$NIGHTLY_VERSION" ] || [ -z "$NIGHTLY_CHECKSUM" ] || [ -z "$NIGHTLY_LINK" ] || [ -z "$NIGHTLY_SIZE" ]; then
            log_message "OTA: Invalid nightly release info (version=$NIGHTLY_VERSION checksum=$NIGHTLY_CHECKSUM link=$NIGHTLY_LINK size=$NIGHTLY_SIZE)"
            display_image_and_text "$BAD_IMG" 35 20 "Update check failed: Invalid nightly release info." 75
            sleep 5
            rm -rf "$TMP_DIR"
            exit 1
        fi
        echo "${NIGHTLY_VERSION}|${NIGHTLY_CHECKSUM}|${NIGHTLY_LINK}|${NIGHTLY_SIZE}|${NIGHTLY_INFO}|FULL|${CURRENT_VERSION}" >> "$TMP_DIR/ota_queue"
        log_message "OTA: Queued full nightly update: $NIGHTLY_VERSION"
    else
        if [ -z "$RELEASE_VERSION" ] || [ -z "$RELEASE_CHECKSUM" ] || [ -z "$RELEASE_LINK" ] || [ -z "$RELEASE_SIZE" ]; then
            log_message "OTA: Invalid release info (version=$RELEASE_VERSION checksum=$RELEASE_CHECKSUM link=$RELEASE_LINK size=$RELEASE_SIZE)"
            display_image_and_text "$BAD_IMG" 35 20 "Update check failed: Invalid release info." 75
            sleep 5
            rm -rf "$TMP_DIR"
            exit 1
        fi
        echo "${RELEASE_VERSION}|${RELEASE_CHECKSUM}|${RELEASE_LINK}|${RELEASE_SIZE}|${RELEASE_INFO}|FULL|${CURRENT_VERSION}" >> "$TMP_DIR/ota_queue"
        log_message "OTA: Queued full stable update: $RELEASE_VERSION"
    fi
}

up_to_date_exit() {
    display_image_and_text "$IMAGE_PATH" 35 25 "System is up to date. Installed version: $CURRENT_VERSION" 75
    sleep 5
    rm -rf "$TMP_DIR"
    exit 0
}

##### MAIN EXECUTION #####

start_pyui_message_writer
display_image_and_text "$IMAGE_PATH" 35 25 "Checking for updates..." 75

# twinkle them lights
rgb_led lrm12 blink2 0000FF 1500 "-1" mmc0

# Fix the wifi first if using an A30 with outdated firmware
if [ "$PLATFORM" = "A30" ]; then
    VERSION="$(cat /usr/miyoo/version)"
    if [ "$VERSION" -lt 20240713100458 ]; then
        jq 'if ."#label" then .label = ."#label" | del(."#label") else . end' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json" > "/mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp" && mv "/mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp" "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
        display_image_and_text "$IMAGE_PATH" 35 25 "Firmware version is too old. Please update your firmware using the Firmware Updater app, then try again." 75
        sleep 5
        exit 1
    fi
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Check for Wi-Fi and active connection
if ! is_wifi_connected; then
    sleep 3
    exit 1
fi

CURRENT_VERSION=$(get_version)
read_only_check

# Try primary and backup URLs
if ! download_release_info "$OTA_URL" "$TMP_DIR/spruce" "$TMP_DIR"; then
    log_message "OTA: Primary URL failed; trying backup URL"
    if ! download_release_info "$OTA_URL_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
        log_message "OTA: First backup URL failed; trying second backup URL"
        if ! download_release_info "$OTA_URL_BACKUP_BACKUP" "$TMP_DIR/spruce" "$TMP_DIR"; then
            display_image_and_text "$IMAGE_PATH" 35 25 "Update check failed; could not get valid update info. Please try again later." 75
            sleep 5
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi
fi

# Extract stable release info (keys are anchored so RELEASE_DIFF_* lines can never match)
RELEASE_VERSION=$(sed -n 's/^RELEASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_CHECKSUM=$(sed -n 's/^RELEASE_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_LINK=$(sed -n 's/^RELEASE_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_SIZE=$(sed -n 's/^RELEASE_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
RELEASE_INFO=$(sed -n 's/^RELEASE_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

# Extract nightly info
NIGHTLY_VERSION=$(sed -n 's/^NIGHTLY_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_CHECKSUM=$(sed -n 's/^NIGHTLY_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_LINK=$(sed -n 's/^NIGHTLY_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_SIZE=$(sed -n 's/^NIGHTLY_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_INFO=$(sed -n 's/^NIGHTLY_INFO=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

# Determine OTA update type
OTA_UPDATE_TYPE="$(get_config_value '.menuOptions."Network Settings".otaUpdateType.selected' "Full")"

# TODO: remove once incremental OTA is approved as stable.
# Incremental updates are limited to developer-mode devices while the
# release pipeline is being proven; everyone else gets the full archive.
if [ "$OTA_UPDATE_TYPE" = "Incremental" ] && ! flag_check "developer_mode"; then
    log_message "OTA: Incremental update type selected without developer_mode; using a full update"
    display_image_and_text "$IMAGE_PATH" 35 25 "Incremental updates are currently limited to developer mode. A full update will be used instead." 75
    sleep 3
    OTA_UPDATE_TYPE="Full"
fi

# "OTA: skip version check" allows re-installing the same (or an older)
# version, e.g. to repair an installation. Developer/tester devices always
# skip it: a nightly cannot be compared against the version file.
SKIP_VERSION_CHECK="$(get_config_value '.menuOptions."Network Settings".otaSkipVersionCheck.selected' "False")"

# Determine desired release channel. Developer/tester devices always follow
# the nightly channel (intended; the previous downloader asked each time).
#
# TODO(OTA): the BETA_* channel in OTA/spruce is not handled here any more;
# those lines are ignored until a beta channel is designed for this flow.
#
# Nightly builds only write the base version to spruce/spruce, so a device
# cannot tell which nightly it has: "already current" cannot be detected for
# nightlies and nightly-to-nightly updates always use the full archive.
TARGET_CHANNEL="stable"

if flag_check "developer_mode" || flag_check "tester_mode"; then
    TARGET_CHANNEL="nightly"
    SKIP_VERSION_CHECK="True"
fi

log_message "OTA: Current version: $CURRENT_VERSION"
log_message "OTA: Update type: $OTA_UPDATE_TYPE"
log_message "OTA: Target channel: $TARGET_CHANNEL"
log_message "OTA: Latest stable version: $RELEASE_VERSION"
log_message "OTA: Latest nightly version: $NIGHTLY_VERSION"

if [ -z "$RELEASE_VERSION" ]; then
    display_image_and_text "$BAD_IMG" 35 20 "Update check failed: Invalid release info." 75
    sleep 5
    rm -rf "$TMP_DIR"
    exit 1
fi

CURRENT_NUM="$(version_num "$CURRENT_VERSION")" || CURRENT_NUM=""
RELEASE_NUM="$(version_num "$RELEASE_VERSION")" || RELEASE_NUM=""

##### BUILD UPDATE QUEUE #####

rm -f "$TMP_DIR/ota_queue"

# Each line in the queue contains:
# VERSION|CHECKSUM|LINK|SIZE|INFO|TYPE|FROM
#
# TYPE is either:
#   FULL
#   DIFF
#   DIFF_NIGHTLY
#
# FROM is the version the archive must be applied on top of. updater.py uses
# it to refuse a queue whose chain does not start at the installed version.
#
# updater.py consumes this queue in order.

# Incremental mode falls back to the traditional full archive whenever no
# usable diff exists, instead of asking the user to change a setting.
USE_INCREMENTAL=0

if [ "$OTA_UPDATE_TYPE" = "Incremental" ]; then
    USE_INCREMENTAL=1

    if [ -z "$CURRENT_NUM" ] || [ -z "$RELEASE_NUM" ]; then
        log_message "OTA: Cannot compare versions ($CURRENT_VERSION vs $RELEASE_VERSION); using a full update"
        USE_INCREMENTAL=0
    elif [ "$CURRENT_NUM" -gt "$RELEASE_NUM" ]; then
        # The installed version is newer than the latest stable release. This
        # is normally a device running a nightly (spruce/spruce holds the base
        # version of the Development branch). No stable diff can start here,
        # and a stable -> nightly diff cannot be applied on top of a nightly.
        if [ "$TARGET_CHANNEL" = "nightly" ]; then
            log_message "OTA: Installed version $CURRENT_VERSION is newer than stable $RELEASE_VERSION; nightly-to-nightly requires a full update"
            USE_INCREMENTAL=0
        else
            log_message "OTA: Installed version $CURRENT_VERSION is newer than stable $RELEASE_VERSION"
            up_to_date_exit
        fi
    fi
fi

if [ "$USE_INCREMENTAL" = "1" ]; then

    # First bring the device up through the stable release chain.
    QUEUE_VERSION="$CURRENT_VERSION"

    while [ "$QUEUE_VERSION" != "$RELEASE_VERSION" ]; do

        QUEUE_VERSION_RE="$(escape_re "$QUEUE_VERSION")"

        # Pick the highest-versioned successor advertised for this version.
        # Do not rely on file order (head -n 1): a stale transition from a
        # withdrawn release could otherwise be selected.
        NEXT_VERSION=""
        NEXT_NUM=0
        for CANDIDATE in $(sed -n "s/^RELEASE_DIFF_LINK_${QUEUE_VERSION_RE}_\([^=]*\)=.*/\1/p" "$TMP_DIR/spruce" | tr -d '\r'); do
            CANDIDATE_NUM="$(version_num "$CANDIDATE")" || continue
            if [ "$CANDIDATE_NUM" -gt "$NEXT_NUM" ]; then
                NEXT_NUM="$CANDIDATE_NUM"
                NEXT_VERSION="$CANDIDATE"
            fi
        done

        if [ -z "$NEXT_VERSION" ]; then
            log_message "OTA: No incremental update found from $QUEUE_VERSION; falling back to a full update"
            display_image_and_text "$IMAGE_PATH" 35 25 "No incremental update path is available from version $QUEUE_VERSION. A full update will be used instead." 75
            sleep 3
            rm -f "$TMP_DIR/ota_queue"
            USE_INCREMENTAL=0
            break
        fi

        # Validate that the metadata actually advances the version.
        # Prevents malformed OTA metadata from creating an infinite loop.
        QUEUE_NUM="$(version_num "$QUEUE_VERSION")" || QUEUE_NUM=""

        if [ -z "$QUEUE_NUM" ] || [ "$NEXT_NUM" -le "$QUEUE_NUM" ]; then
            log_message "OTA: Incremental update does not advance version: $QUEUE_VERSION -> $NEXT_VERSION"
            display_image_and_text "$BAD_IMG" 35 25 "Invalid incremental update path. Please try again later or use Full update mode." 75
            sleep 5
            rm -rf "$TMP_DIR"
            exit 1
        fi

        NEXT_VERSION_RE="$(escape_re "$NEXT_VERSION")"
        DIFF_LINK=$(sed -n "s/^RELEASE_DIFF_LINK_${QUEUE_VERSION_RE}_${NEXT_VERSION_RE}=//p" "$TMP_DIR/spruce" | head -n 1 | tr -d '\n\r')
        DIFF_CHECKSUM=$(sed -n "s/^RELEASE_DIFF_CHECKSUM_${QUEUE_VERSION_RE}_${NEXT_VERSION_RE}=//p" "$TMP_DIR/spruce" | head -n 1 | tr -d '\n\r')
        DIFF_SIZE=$(sed -n "s/^RELEASE_DIFF_SIZE_IN_MB_${QUEUE_VERSION_RE}_${NEXT_VERSION_RE}=//p" "$TMP_DIR/spruce" | head -n 1 | tr -d '\n\r')

        if [ -z "$DIFF_CHECKSUM" ] || [ -z "$DIFF_SIZE" ] || [ -z "$DIFF_LINK" ]; then
            log_message "OTA: Incomplete incremental metadata for $QUEUE_VERSION -> $NEXT_VERSION"
            display_image_and_text "$BAD_IMG" 35 25 "Update information is incomplete. Please try again later." 75
            sleep 5
            rm -rf "$TMP_DIR"
            exit 1
        fi

        echo "${NEXT_VERSION}|${DIFF_CHECKSUM}|${DIFF_LINK}|${DIFF_SIZE}|${RELEASE_INFO}|DIFF|${QUEUE_VERSION}" >> "$TMP_DIR/ota_queue"

        log_message "OTA: Queued incremental update: $QUEUE_VERSION -> $NEXT_VERSION"

        QUEUE_VERSION="$NEXT_VERSION"
    done

fi

if [ "$USE_INCREMENTAL" = "1" ] && [ "$TARGET_CHANNEL" = "nightly" ]; then

    # The desired channel is nightly: add the stable -> nightly incremental
    # update after reaching the latest stable release.
    NIGHTLY_DIFF_BASE_VERSION=$(sed -n 's/^NIGHTLY_DIFF_BASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r' | sed 's/^v//')
    NIGHTLY_DIFF_VERSION=$(sed -n 's/^NIGHTLY_DIFF_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_DIFF_LINK=$(sed -n 's/^NIGHTLY_DIFF_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_DIFF_CHECKSUM=$(sed -n 's/^NIGHTLY_DIFF_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_DIFF_SIZE=$(sed -n 's/^NIGHTLY_DIFF_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

    if [ -z "$NIGHTLY_DIFF_LINK" ] || [ -z "$NIGHTLY_DIFF_CHECKSUM" ] || [ -z "$NIGHTLY_DIFF_SIZE" ] || [ -z "$NIGHTLY_VERSION" ]; then
        log_message "OTA: Nightly incremental metadata is not available; falling back to a full nightly update"
        rm -f "$TMP_DIR/ota_queue"
        USE_INCREMENTAL=0
    elif [ "$NIGHTLY_DIFF_BASE_VERSION" != "$RELEASE_VERSION" ] || { [ -n "$NIGHTLY_DIFF_VERSION" ] && [ "$NIGHTLY_DIFF_VERSION" != "$NIGHTLY_VERSION" ]; }; then
        # Every nightly diff is generated from one specific stable release.
        # If a new stable was published after the last nightly build, the
        # diff would be applied on top of the wrong base and mix two trees.
        log_message "OTA: Nightly diff base $NIGHTLY_DIFF_BASE_VERSION (version $NIGHTLY_DIFF_VERSION) does not match stable $RELEASE_VERSION / nightly $NIGHTLY_VERSION; falling back to a full nightly update"
        display_image_and_text "$IMAGE_PATH" 35 25 "The nightly incremental package was not built against the latest stable release. A full nightly update will be used instead." 75
        sleep 3
        rm -f "$TMP_DIR/ota_queue"
        USE_INCREMENTAL=0
    else
        echo "${NIGHTLY_VERSION}|${NIGHTLY_DIFF_CHECKSUM}|${NIGHTLY_DIFF_LINK}|${NIGHTLY_DIFF_SIZE}|${NIGHTLY_INFO}|DIFF_NIGHTLY|${RELEASE_VERSION}" >> "$TMP_DIR/ota_queue"
        log_message "OTA: Queued nightly incremental update: $RELEASE_VERSION -> $NIGHTLY_VERSION"
    fi
fi

if [ "$USE_INCREMENTAL" != "1" ]; then
    # Full update mode (or incremental fallback).
    if [ "$SKIP_VERSION_CHECK" != "True" ] && [ "$TARGET_CHANNEL" = "stable" ]; then
        # Never re-download or downgrade when the installed stable release is
        # already current ("OTA: skip version check" allows a reinstall).
        if [ -n "$CURRENT_NUM" ] && [ -n "$RELEASE_NUM" ] && [ "$RELEASE_NUM" -le "$CURRENT_NUM" ]; then
            log_message "OTA: Latest stable $RELEASE_VERSION is not newer than installed $CURRENT_VERSION"
            up_to_date_exit
        fi
    fi

    queue_full_update
fi

##### VERIFY UPDATE QUEUE #####

if [ ! -s "$TMP_DIR/ota_queue" ]; then
    up_to_date_exit
fi

QUEUE_COUNT=$(wc -l < "$TMP_DIR/ota_queue" | tr -d ' ')
FINAL_VERSION=$(tail -n 1 "$TMP_DIR/ota_queue" | cut -d'|' -f1)
FINAL_INFO=$(tail -n 1 "$TMP_DIR/ota_queue" | cut -d'|' -f5)
TOTAL_SIZE=0

while IFS='|' read -r _ _ _ QUEUE_SIZE _ _ _; do
    case "$QUEUE_SIZE" in
        ''|*[!0-9]*) ;;
        *) TOTAL_SIZE=$((TOTAL_SIZE + QUEUE_SIZE)) ;;
    esac
done < "$TMP_DIR/ota_queue"

log_message "OTA: Update queue contains $QUEUE_COUNT archive(s), ${TOTAL_SIZE} MB, final version $FINAL_VERSION"

##### CONFIRM BEFORE DOWNLOADING #####

if [ -z "$FINAL_INFO" ]; then
    FINAL_INFO="https://github.com/spruceUI/spruceOS/releases/latest"
fi

update_qr_code="$(qr_code -t "$FINAL_INFO")"
display_image_and_text "$update_qr_code" 50 5 "Scan QR code for release notes. New version available: $FINAL_VERSION ($QUEUE_COUNT package(s), about ${TOTAL_SIZE} MB). Press A to download and install, or B to cancel." 75

if confirm 300; then
    log_message "OTA: User confirmed download"
else
    log_message "OTA: User did not confirm download"
    display_image_and_text "$BAD_IMG" 35 20 "Update cancelled." 75
    sleep 3
    rm -rf "$TMP_DIR"
    exit 0
fi

##### DOWNLOAD ALL REQUIRED ARCHIVES #####

rm -rf "$TMP_DIR/downloads"
mkdir -p "$TMP_DIR/downloads"

QUEUE_NUMBER=0

while IFS='|' read -r QUEUE_VERSION QUEUE_CHECKSUM QUEUE_LINK QUEUE_SIZE QUEUE_INFO QUEUE_TYPE QUEUE_FROM; do

    QUEUE_NUMBER=$((QUEUE_NUMBER + 1))

    FILENAME=$(echo "$QUEUE_LINK" | sed 's/.*\///')
    OUTPUT_FILE="/mnt/SDCARD/$FILENAME"

    log_message "OTA: Processing archive $QUEUE_NUMBER/$QUEUE_COUNT: $QUEUE_FROM -> $QUEUE_VERSION ($QUEUE_TYPE)"

    display_image_and_text "$IMAGE_PATH" 35 25 "Preparing update $QUEUE_NUMBER of $QUEUE_COUNT..." 75

    # Check if the file already exists and is valid.
    if [ -f "$OUTPUT_FILE" ]; then
        log_message "OTA: Update file already exists: $FILENAME"
        display_image_and_text "$IMAGE_PATH" 35 25 "Update file already exists. Verifying..." 75

        if verify_checksum "$OUTPUT_FILE" "$QUEUE_CHECKSUM"; then
            log_message "OTA: Existing file verified: $FILENAME"
            continue
        else
            log_message "OTA: Existing file failed verification; downloading again."
        fi
    fi

    # Check free disk space before each download.
    sdcard_mountpoint="$(mount | grep -m 1 "$SD_MOUNTPOINT" | awk '{print $1}')"
    sdcard_freespace="$(df -m "$sdcard_mountpoint" | awk 'NR==2{print $4}')"
    min_install_space=$(((QUEUE_SIZE * 2) + 128))

    if [ "$sdcard_freespace" -lt "$min_install_space" ]; then
        log_message "OTA: Not enough free space on SD card for $FILENAME"
        display_image_and_text "$IMAGE_PATH" 35 25 "Insufficient space on SD card. At least $min_install_space MB of space should be free." 75
        sleep 5
        rm -rf "$TMP_DIR"
        exit 1
    fi

    display_image_and_text "$IMAGE_PATH" 35 25 "Downloading update $QUEUE_NUMBER of $QUEUE_COUNT..." 75

    if ! download_and_display_progress "$QUEUE_LINK" "$OUTPUT_FILE" "spruce v${QUEUE_VERSION}" "$((QUEUE_SIZE * 1024 * 1024))"; then
        log_message "OTA: Failed downloading $FILENAME"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    display_image_and_text "$IMAGE_PATH" 35 25 "Download complete! Verifying..." 75

    if ! verify_checksum "$OUTPUT_FILE" "$QUEUE_CHECKSUM"; then
        display_image_and_text "$BAD_IMG" 35 25 "File downloaded but failed verification. Try again..." 75
        sleep 5
        rm -rf "$TMP_DIR"
        exit 1
    fi

    log_message "OTA: Verified $FILENAME"
    vibrate &

done < "$TMP_DIR/ota_queue"

##### PREPARE FOR INSTALLATION #####

sync

# Show updater app
jq 'if ."#label" then .label = ."#label" | del(."#label") else . end' "/mnt/SDCARD/App/-Updater/config.json" > "/mnt/SDCARD/App/-Updater/config.json.tmp" && mv "/mnt/SDCARD/App/-Updater/config.json.tmp" "/mnt/SDCARD/App/-Updater/config.json"

# Check battery level before asking to update
BATTERY_CAPACITY="$(device_get_battery_percent)"
CHARGING="$(device_get_charging_status)"

if [ "$BATTERY_CAPACITY" -lt 20 ] && [ "$CHARGING" = "Discharging" ]; then
    display_image_and_text "$BAD_IMG" 35 25 "Battery too low to safely update. Please charge to at least 20% or plug in your device. You can run the EZ Updater app to install the already downloaded updates." 75
    sleep 5
    exit 0
fi

# Update script call
display_image_and_text "$IMAGE_PATH" 35 25 "Download successful! Press A to install now, or B to exit and install later." 75

if confirm 30 0; then
    log_message "OTA: Update confirmed"
    "$(get_python_path)" /mnt/SDCARD/App/-Updater/updater.py
else
    log_message "OTA: Update declined"
    exit 0
fi