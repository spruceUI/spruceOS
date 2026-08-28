#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/update.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"

OTA_URL="https://spruceui.github.io/OTA/spruce"
OTA_URL_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceui.github.io/refs/heads/main/OTA/spruce"
OTA_URL_BACKUP_BACKUP="https://raw.githubusercontent.com/spruceUI/spruceSource/refs/heads/main/OTA/spruce"
TMP_DIR="/mnt/SDCARD/App/-OTA/tmp"
# Written by updater.py after a nightly install: the stable release that
# nightly was generated from. Absent on stable installs.
NIGHTLY_BASE_FILE="/mnt/SDCARD/Saves/spruce/ota_nightly_base"

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

# Build identity of the installed nightly: the commit the package was built
# from. The nightly workflow writes "Last commit: <sha>" into
# /mnt/SDCARD/commits_nightly.txt and ships that file in every nightly
# package (full and diff), so any install - updater, PC installer or a
# manual copy - identifies itself. Several nightlies built on one day share
# a version string; this tells a rebuild from the build already installed.
# Prints nothing when unknown.
#
# TODO(OTA, future wave): a build counter in the nightly version itself
# (e.g. 4.3.6-20260827.2) would make this and NIGHTLY_COMMIT unnecessary.
# Keep every identity reader in this function so that swap is a one-place
# change (the boot-time checker in runtimeHelper.sh mirrors it).
installed_nightly_build() {
    sed -n 's/^Last commit: *//p' /mnt/SDCARD/commits_nightly.txt 2>/dev/null | head -n 1 | tr -d '[:space:]' | tr 'A-F' 'a-f'
}

# Short form of a build identity for messages.
short_build() {
    printf '%s' "$1" | cut -c1-7
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
        # FROM of a full nightly is the stable release it was generated from
        # (recorded on the device by updater.py); empty if the metadata does
        # not say, in which case later nightly diffs fall back to full.
        echo "${NIGHTLY_VERSION}|${NIGHTLY_CHECKSUM}|${NIGHTLY_LINK}|${NIGHTLY_SIZE}|${NIGHTLY_INFO}|FULL|${NIGHTLY_DIFF_BASE_VERSION}" >> "$TMP_DIR/ota_queue"
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

# Is the installed nightly strictly NEWER than the advertised one? Base
# versions compare numerically; equal bases compare by the date suffix.
#
# Strictly newer, not "at least as new": an advertised nightly carrying the
# same version as the installed one is still offered. More than one nightly is
# sometimes spun on a single date, so an equal date does not mean equal build,
# and being able to re-take the current one is how the OTA path gets tested at
# all. Only a device that is genuinely ahead of what is advertised - a nightly
# newer than the published one - is told it is up to date.
nightly_is_newer_than_advertised() {
    local installed_num target_num installed_date target_date
    installed_num="$(version_num "$INSTALLED_NIGHTLY_VERSION")" || return 1
    target_num="$(version_num "$NIGHTLY_VERSION")" || return 1
    [ "$target_num" -gt "$installed_num" ] && return 1
    [ "$target_num" -lt "$installed_num" ] && return 0
    installed_date="${INSTALLED_NIGHTLY_VERSION##*-}"
    target_date="${NIGHTLY_VERSION##*-}"
    case "$installed_date$target_date" in
        ""|*[!0-9]*) return 1 ;;
    esac
    [ "$target_date" -ge "$installed_date" ] && return 1
    return 0
}

# Optional $1 replaces the generic sentence, e.g. when the device is ahead
# of the update feed.
up_to_date_exit() {
    local installed="${INSTALLED_NIGHTLY_VERSION:-$CURRENT_VERSION}"
    [ -n "$INSTALLED_NIGHTLY_BUILD" ] && installed="$installed ($(short_build "$INSTALLED_NIGHTLY_BUILD"))"
    display_image_and_text "$IMAGE_PATH" 35 25 "${1:-System is up to date.} Installed version: $installed" 75
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
INSTALLED_NIGHTLY_BASE="$(cat "$NIGHTLY_BASE_FILE" 2>/dev/null | tr -d '[:space:]' | sed 's/^v//; s/-.*$//')"
# Full version of an installed nightly, e.g. 4.3.6-20260828, when the install
# left its root marker (/mnt/SDCARD/<base>-<date>, read by get_version_complex).
INSTALLED_NIGHTLY_VERSION=""
INSTALLED_FULL_VERSION="$(get_version_complex)"
if [ -n "$INSTALLED_FULL_VERSION" ] && [ "$INSTALLED_FULL_VERSION" != "$CURRENT_VERSION" ]; then
    INSTALLED_NIGHTLY_VERSION="$INSTALLED_FULL_VERSION"
fi
INSTALLED_NIGHTLY_BUILD=""
if [ -n "$INSTALLED_NIGHTLY_VERSION" ]; then
    INSTALLED_NIGHTLY_BUILD="$(installed_nightly_build)"
fi
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
# Commit the published nightly was built from (see installed_nightly_build).
NIGHTLY_COMMIT=$(sed -n 's/^NIGHTLY_COMMIT=//p' "$TMP_DIR/spruce" | tr -d '\n\r' | tr 'A-F' 'a-f')

# Determine OTA update type
OTA_UPDATE_TYPE="$(get_config_value '.menuOptions."Network Settings".otaUpdateType.selected' "Full")"

# TODO: remove once incremental OTA is approved as stable.
# Incremental updates are limited to developer/tester devices while the
# release pipeline is being proven; everyone else gets the full archive.
if [ "$OTA_UPDATE_TYPE" = "Incremental" ] && ! flag_check "developer_mode" && ! flag_check "tester_mode"; then
    log_message "OTA: Incremental update type selected without developer_mode/tester_mode; using a full update"
    display_image_and_text "$IMAGE_PATH" 35 25 "Incremental updates are currently limited to developer or tester mode. A full update will be used instead." 75
    sleep 3
    OTA_UPDATE_TYPE="Full"
fi

# "OTA: skip version check" allows re-installing the same (or an older)
# stable release, e.g. to repair an installation, and lets a nightly device
# take an advertised nightly that is OLDER than the installed one. The same
# nightly version is always offered again (see nightly_is_newer_than_advertised).
SKIP_VERSION_CHECK="$(get_config_value '.menuOptions."Network Settings".otaSkipVersionCheck.selected' "False")"

# Determine desired release channel. Developer/tester devices follow the
# nightly channel unless "OTA: release channel" is set to Stable; that choice
# exists so the stable->stable incremental path can be exercised while
# incremental updates are gated behind developer mode. Everybody else always
# follows the stable channel.
#
# TODO(OTA): the BETA_* channel in OTA/spruce is not handled here any more;
# those lines are ignored until a beta channel is designed for this flow.
#
# A nightly device knows its version from the root marker
# (/mnt/SDCARD/<base>-<date>), its build from commits_nightly.txt and its
# stable base from NIGHTLY_BASE_FILE. Nightly-to-nightly updates only need
# the base: every nightly diff is generated from the current stable release
# and covers every path touched since it, so it applies on top of any
# nightly with the same recorded base.
OTA_CHANNEL="$(get_config_value '.menuOptions."Network Settings".otaChannel.selected' "Nightly")"
TARGET_CHANNEL="stable"

if flag_check "developer_mode" || flag_check "tester_mode"; then
    if [ "$OTA_CHANNEL" = "Stable" ]; then
        TARGET_CHANNEL="stable"
    else
        TARGET_CHANNEL="nightly"
    fi
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

# Nightly incremental metadata. Every nightly diff is generated from one
# specific stable release and covers every path touched since it, so it can
# be applied on top of that stable OR on top of any nightly derived from it.
# It is only usable when it was built from the CURRENT stable release.
NIGHTLY_DIFF_BASE_VERSION=$(sed -n 's/^NIGHTLY_DIFF_BASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r' | sed 's/^v//')
NIGHTLY_DIFF_VERSION=$(sed -n 's/^NIGHTLY_DIFF_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_DIFF_LINK=$(sed -n 's/^NIGHTLY_DIFF_LINK=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_DIFF_CHECKSUM=$(sed -n 's/^NIGHTLY_DIFF_CHECKSUM=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
NIGHTLY_DIFF_SIZE=$(sed -n 's/^NIGHTLY_DIFF_SIZE_IN_MB=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

NIGHTLY_DIFF_OK=0
if [ -n "$NIGHTLY_DIFF_LINK" ] && [ -n "$NIGHTLY_DIFF_CHECKSUM" ] && [ -n "$NIGHTLY_DIFF_SIZE" ] && [ -n "$NIGHTLY_VERSION" ] \
    && [ "$NIGHTLY_DIFF_BASE_VERSION" = "$RELEASE_VERSION" ] \
    && { [ -z "$NIGHTLY_DIFF_VERSION" ] || [ "$NIGHTLY_DIFF_VERSION" = "$NIGHTLY_VERSION" ]; }; then
    NIGHTLY_DIFF_OK=1
fi

log_message "OTA: Installed nightly base: ${INSTALLED_NIGHTLY_BASE:-none}; installed nightly version: ${INSTALLED_NIGHTLY_VERSION:-none}; installed build: ${INSTALLED_NIGHTLY_BUILD:-unknown}; published build: ${NIGHTLY_COMMIT:-unknown}; nightly diff base: ${NIGHTLY_DIFF_BASE_VERSION:-none} (usable: $NIGHTLY_DIFF_OK)"

# A nightly that knows its own version is not offered an OLDER nightly. The
# same version is still offered - see nightly_is_newer_than_advertised.
if [ "$TARGET_CHANNEL" = "nightly" ] && [ "$SKIP_VERSION_CHECK" != "True" ] && [ -n "$INSTALLED_NIGHTLY_VERSION" ] && nightly_is_newer_than_advertised; then
    # The feed lags a publish (or a publish half-failed): say so instead
    # of "up to date", which sends testers looking in the wrong place.
    log_message "OTA: Installed nightly $INSTALLED_NIGHTLY_VERSION is newer than the published nightly $NIGHTLY_VERSION"
    up_to_date_exit "Installed nightly $INSTALLED_NIGHTLY_VERSION is newer than the published nightly $NIGHTLY_VERSION; the update feed may not have been refreshed yet."
fi

# When the advertised nightly IS the installed version, say what a re-take
# means: the same build again (a plain reinstall), a rebuild with the same
# version string, or unknown (no build identity on either side). The offer
# itself does not depend on this; only the log line and the prompt do.
NIGHTLY_SAME_VERSION=0
NIGHTLY_SAME_BUILD=0
if [ "$TARGET_CHANNEL" = "nightly" ] && [ -n "$INSTALLED_NIGHTLY_VERSION" ] && [ "$INSTALLED_NIGHTLY_VERSION" = "$NIGHTLY_VERSION" ]; then
    NIGHTLY_SAME_VERSION=1
    if [ -z "$INSTALLED_NIGHTLY_BUILD" ] || [ -z "$NIGHTLY_COMMIT" ]; then
        log_message "OTA: Nightly $NIGHTLY_VERSION is already installed (build unknown); offering it again"
    elif [ "$INSTALLED_NIGHTLY_BUILD" = "$NIGHTLY_COMMIT" ]; then
        NIGHTLY_SAME_BUILD=1
        log_message "OTA: Nightly $NIGHTLY_VERSION ($(short_build "$NIGHTLY_COMMIT")) is already installed; offering a reinstall"
    else
        log_message "OTA: Nightly $NIGHTLY_VERSION was rebuilt since it was installed (installed $(short_build "$INSTALLED_NIGHTLY_BUILD"), published $(short_build "$NIGHTLY_COMMIT")); offering it again"
    fi
fi

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
NIGHTLY_QUEUED=0

if [ "$OTA_UPDATE_TYPE" = "Incremental" ]; then
    USE_INCREMENTAL=1

    if [ -z "$CURRENT_NUM" ] || [ -z "$RELEASE_NUM" ]; then
        log_message "OTA: Cannot compare versions ($CURRENT_VERSION vs $RELEASE_VERSION); using a full update"
        USE_INCREMENTAL=0
    elif [ -n "$INSTALLED_NIGHTLY_BASE" ]; then
        # The device runs a nightly. The stable chain never applies on top
        # of a nightly; the only incremental path is the nightly diff, and
        # only when that nightly was generated from the same stable release
        # as the installed one.
        if [ "$TARGET_CHANNEL" = "nightly" ] && [ "$NIGHTLY_DIFF_OK" = "1" ] && [ "$INSTALLED_NIGHTLY_BASE" = "$RELEASE_VERSION" ]; then
            echo "${NIGHTLY_VERSION}|${NIGHTLY_DIFF_CHECKSUM}|${NIGHTLY_DIFF_LINK}|${NIGHTLY_DIFF_SIZE}|${NIGHTLY_INFO}|DIFF_NIGHTLY|${RELEASE_VERSION}" >> "$TMP_DIR/ota_queue"
            log_message "OTA: Queued nightly incremental update on top of nightly $CURRENT_VERSION (stable base $INSTALLED_NIGHTLY_BASE): -> $NIGHTLY_VERSION"
            NIGHTLY_QUEUED=1
        elif [ "$TARGET_CHANNEL" = "nightly" ]; then
            log_message "OTA: Nightly diff not applicable on this nightly (installed base $INSTALLED_NIGHTLY_BASE, diff base ${NIGHTLY_DIFF_BASE_VERSION:-none}, stable $RELEASE_VERSION); falling back to a full nightly update"
            USE_INCREMENTAL=0
        else
            log_message "OTA: Device runs a nightly (base $INSTALLED_NIGHTLY_BASE) on the stable channel; using a full update"
            USE_INCREMENTAL=0
        fi
    elif [ "$CURRENT_NUM" -gt "$RELEASE_NUM" ]; then
        # Newer than the latest stable without a recorded nightly base: a
        # nightly installed before the base was recorded, or an unknown
        # state. No diff can be trusted here.
        if [ "$TARGET_CHANNEL" = "nightly" ]; then
            log_message "OTA: Installed version $CURRENT_VERSION is newer than stable $RELEASE_VERSION and has no recorded nightly base; using a full nightly update"
            USE_INCREMENTAL=0
        else
            log_message "OTA: Installed version $CURRENT_VERSION is newer than stable $RELEASE_VERSION"
            up_to_date_exit
        fi
    fi
fi

if [ "$USE_INCREMENTAL" = "1" ] && [ "$NIGHTLY_QUEUED" != "1" ]; then

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

if [ "$USE_INCREMENTAL" = "1" ] && [ "$NIGHTLY_QUEUED" != "1" ] && [ "$TARGET_CHANNEL" = "nightly" ]; then

    # The desired channel is nightly: add the stable -> nightly incremental
    # update after reaching the latest stable release.
    if [ "$NIGHTLY_DIFF_OK" = "1" ]; then
        echo "${NIGHTLY_VERSION}|${NIGHTLY_DIFF_CHECKSUM}|${NIGHTLY_DIFF_LINK}|${NIGHTLY_DIFF_SIZE}|${NIGHTLY_INFO}|DIFF_NIGHTLY|${RELEASE_VERSION}" >> "$TMP_DIR/ota_queue"
        log_message "OTA: Queued nightly incremental update: $RELEASE_VERSION -> $NIGHTLY_VERSION"
    elif [ -z "$NIGHTLY_DIFF_LINK" ] || [ -z "$NIGHTLY_DIFF_CHECKSUM" ] || [ -z "$NIGHTLY_DIFF_SIZE" ] || [ -z "$NIGHTLY_VERSION" ]; then
        log_message "OTA: Nightly incremental metadata is not available; falling back to a full nightly update"
        rm -f "$TMP_DIR/ota_queue"
        USE_INCREMENTAL=0
    else
        # The nightly diff was generated against a different stable release
        # (e.g. a new stable was published after the last nightly build).
        # Applying it on top of $RELEASE_VERSION would mix two trees.
        log_message "OTA: Nightly diff base $NIGHTLY_DIFF_BASE_VERSION (version $NIGHTLY_DIFF_VERSION) does not match stable $RELEASE_VERSION / nightly $NIGHTLY_VERSION; falling back to a full nightly update"
        display_image_and_text "$IMAGE_PATH" 35 25 "The nightly incremental package was not built against the latest stable release. A full nightly update will be used instead." 75
        sleep 3
        rm -f "$TMP_DIR/ota_queue"
        USE_INCREMENTAL=0
    fi
fi

if [ "$USE_INCREMENTAL" != "1" ]; then
    # Full update mode (or incremental fallback).
    if [ "$SKIP_VERSION_CHECK" != "True" ] && [ "$TARGET_CHANNEL" = "stable" ] && [ -z "$INSTALLED_NIGHTLY_BASE" ]; then
        # Never re-download or downgrade when the installed stable release is
        # already current ("OTA: skip version check" allows a reinstall). A
        # device that runs a nightly is not on any stable release, so on the
        # stable channel it is always offered the full stable archive.
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

UPDATE_PROMPT="New version available: $FINAL_VERSION"
if [ "$NIGHTLY_SAME_VERSION" = "1" ] && [ "$FINAL_VERSION" = "$NIGHTLY_VERSION" ]; then
    if [ "$NIGHTLY_SAME_BUILD" = "1" ]; then
        UPDATE_PROMPT="Nightly $FINAL_VERSION ($(short_build "$NIGHTLY_COMMIT")) is already installed; this reinstalls the same build"
    elif [ -n "$INSTALLED_NIGHTLY_BUILD" ] && [ -n "$NIGHTLY_COMMIT" ]; then
        UPDATE_PROMPT="Nightly $FINAL_VERSION was rebuilt since it was installed (installed $(short_build "$INSTALLED_NIGHTLY_BUILD"), published $(short_build "$NIGHTLY_COMMIT"))"
    else
        UPDATE_PROMPT="Nightly $FINAL_VERSION is already installed; it may have been rebuilt since"
    fi
elif [ "$FINAL_VERSION" = "$NIGHTLY_VERSION" ] && [ -n "$NIGHTLY_COMMIT" ]; then
    UPDATE_PROMPT="New version available: $FINAL_VERSION ($(short_build "$NIGHTLY_COMMIT"))"
fi

update_qr_code="$(qr_code -t "$FINAL_INFO")"
display_image_and_text "$update_qr_code" 50 5 "Scan QR code for release notes. $UPDATE_PROMPT ($QUEUE_COUNT package(s), about ${TOTAL_SIZE} MB). Press A to download and install, or B to cancel." 75

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