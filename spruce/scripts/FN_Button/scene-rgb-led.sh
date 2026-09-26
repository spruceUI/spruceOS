#!/bin/sh
# Switch scene action: toggle the RGB LEDs through spruce's own LED system.
#
# trimui_scened runs this with arg 1 (switch on) / 0 (switch off). The stock
# com.trimui.ledc.sh cannot be used here: it derives brightness from the TrimUI
# shared-memory var (shmvar 10), which spruce never populates (spruce drives the
# LEDs via rgb_led / the RGB LED Settings instead), so on this device shmvar 10 is
# 0 and ledc.sh always resolves to max_scale 0 (LEDs dark) regardless of switch
# position. Going through rgb_led_trimui keeps the switch in sync with spruce's
# own LED state, the LEDmaxScale brightness, and the disableLEDs setting.

case "$1" in
    1)
        [ -x /usr/trimui/bin/shmvar ] && /usr/trimui/bin/shmvar ledswitch 0 2>/dev/null
        mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
        echo 0 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
        ;;
    0)
        [ -x /usr/trimui/bin/shmvar ] && /usr/trimui/bin/shmvar ledswitch 1 2>/dev/null
        mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
        echo 1 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
        ;;
esac

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


are_emu_specific_leds_enabled() {
    enabled="$(get_config_value '.menuOptions."RGB LED Settings".enableEmuSpecificLEDbehavior.selected' "True")"
    [ "$enabled" = "True" ]
}

is_emu_running() {
    grep -q "standard_launch.sh" /tmp/cmd_to_run.sh
}

get_emu_dir() {
	sed 's|^.*"\([^"]*\)/../../spruce/scripts/emu/standard_launch\.sh.*|\1|' /tmp/cmd_to_run.sh
}

get_emu_color() {
    emu_json="$(get_emu_dir)/config.json"
    emu_color="$(jq -r '.themecolor' "$emu_json")"
    if [ -z "$emu_color" ] || [ "$emu_color" = "null" ]; then
        emu_color="FFFFFF"
    fi
    echo "$emu_color"
}



# Note: rgb_led_trimui "off" sets effect=0 (disable), which only FREEZES the
# animation engine -- the LEDs keep their last lit colour rather than going dark.
# To actually extinguish them we drive a static effect with colour 000000.
# The black write below only holds until something else writes a colour, and
# plenty does: principal.sh runs set_rgb_in_menu on every return to the menu, and
# led_effect re-colours on every game launch. So record the state in a flag that
# rgb_led_trimui honours, and the LEDs stay off until this action turns them back
# on. Order matters both ways - write while the flag is clear, or rgb_led_trimui
# early-outs on our own call.
case "$1" in
    1)  # switch on -> LEDs off (black)
        flag_remove "leds_forced_off"
        rgb_led lrm12b static "000000"
        flag_add "leds_forced_off" --tmp
        ;;
    0)  # switch off -> LEDs on (configured colour)
        flag_remove "leds_forced_off"
        if are_emu_specific_leds_enabled && is_emu_running; then
            color="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDcolor.selected' "White")"
            effect="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDeffect.selected' "breathe")"
            duration="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDduration.selected' "4000")"
        else
            color="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDcolor.selected' "White")"
            effect="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDeffect.selected' "static")"
            duration="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDduration.selected' "2000")"
        fi
        if [ "$color" = "System-specific" ]; then
            hex="$(get_emu_color)"
        else
            hex="$(map_color_name_to_hex "$color")"
        fi
        rgb_led lrm12b "$effect" "$hex" "$duration" "-1"
        ;;
esac
