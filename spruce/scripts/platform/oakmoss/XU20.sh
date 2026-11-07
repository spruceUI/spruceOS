#!/bin/sh

# MagicX / XU RETRO XU20 V32. Everything lives in MagicXCommon.sh; this file only
# names the device's own config. The Hynitron touch node is resolved at device_init.

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/MagicXCommon.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-xu20-system.json"
}

# The XU20's extra face button, on images that give it KEY_HOMEPAGE (B_HOME in XU20.cfg):
# the same Home action as the Smart Pro S's top button (buttons_watchdog.sh calls this).
device_home_button_pressed() {
    action="$(get_config_value '.menuOptions."Button Settings".homeAction.selected' "Game Switcher")"
    perform_action "$action"
    case "$action" in
        "Game Switcher"|"Exit game")
            rm -f /tmp/cmd_to_run.sh
            rm -f /mnt/SDCARD/spruce/flags/lastgame.lock
            ;;
    esac
}
