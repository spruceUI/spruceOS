#!/bin/sh
# Boot work that doesn't need to beat the menu: the WiFi bring-up and RAOfflineProxy.
# Started beside PyUI, they slow its first frame, most on two-core devices like the Mini.
#
# PyUI runs this after every first frame (firstFrameCmd in App/PyUI/py-ui-config.json).
# runtime.sh runs it straight away on boots that don't show the menu first, and again
# after a timeout in case PyUI never draws. Only the first call of a boot does anything.

# miyoo_mini_startup.sh waits for this directory before its own WiFi bring-up
mkdir /tmp/spruce_boot_jobs_started 2>/dev/null || exit 0

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

log_message "Starting WiFi and RAOfflineProxy (${1:-first frame})"
# The proxy goes first: on boots without the menu a game follows at once, and RetroArch
# logs in to it. Not gated on WiFi, since achievements are earned offline.
# Backgrounded: stopping a disabled proxy runs its Python backend.
raproxy_apply &

# Read PyUI's CJK fallback font into the page cache so its first use is not a cold
# SD read. Not on the Minis: with 128 MB the cache would be evicted before use.
if [ "$PLATFORM_FAMILY" != "miyoomini" ]; then
    case "$(get_ui_language)" in
        "Chinese (S)"|"Chinese (T)"|Japanese|Korean)
            font="$(jq -r '.fallbackFontPath // empty' /mnt/SDCARD/App/PyUI/py-ui-config.json 2>/dev/null)"
            [ -f "$font" ] && cat "$font" >/dev/null 2>&1 &
            ;;
    esac
fi

wifi_request apply
