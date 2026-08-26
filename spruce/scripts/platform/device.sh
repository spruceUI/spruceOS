#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

get_python_path() {
    log_message "Missing get_python_path function"
}

get_config_path() {
    log_message "Missing get_config_path function"
}

cores_online() {
    log_message "Missing cores_online function"
}

set_smart() {
    log_message "Missing set_smart function"
}

set_performance() {
    log_message "Missing set_performance function"
}

set_overclock() {
    log_message "Missing set_overclock function"
}

set_powersave() {
    log_message "Missing set_powersave function -- using smart"
    set_smart
}

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    log_message "Missing vibrate function"
}

# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    log_message "Missing display_kill function"
}


# Call this to display text on the screen
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL display_kill()
# It's possible to leave a display process running
# Usage: display [options]
# Options:
#   -i, --image <path>    Image path (default: DEFAULT_IMAGE)
#   -t, --text <text>     Text to display
#   -d, --delay <seconds> Delay in seconds (default: 0)
#   -s, --size <size>     Text size (default: 36)
#   -p, --position <pos>  Text position as percentage from the top of the screen
#   (Text is offset from it's center, images are offset from the top of the image)
#   -a, --align <align>   Text alignment (left, middle, right) (default: middle)
#   -w, --width <width>   Text width (default: 600)
#   -c, --color <color>   Text color in RGB format (default: dbcda7) Spruce text yellow
#   -f, --font <path>     Font path (optional)
#   -o, --okay            Use ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE and runs acknowledge()
#   -bg, --bg-color <color> Background color in RGB format (default: 7f7f7f)
#   -bga, --bg-alpha <alpha> Background alpha value (0-255, default: 0)
#   -is, --image-scaling <scale> Image scaling factor (default: 1.0)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000
# Calling display with -o/--okay will use the ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE
# Calling display with --confirm will use the CONFIRM_IMAGE instead of DEFAULT_IMAGE
# If using --confirm, you should call the confirm() message in an if block in your script
# --confirm will supercede -o/--okay
# You can also call infinite image layers with (next-image.png scale height side)*
#   --icon <path>         Path to an icon image to display on top (default: none)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000 --icon "/path/to/icon.png"
display() {
    log_message "Missing display function"
}


# ---------------------------------------------------------------------------
# rgb_led <zones> <effect> [color] [duration_ms] [cycles] [Flip led trigger]
#
# Controls RGB LEDs on TrimUI Brick / Smart Pro.
#
# PARAMETERS:
#   <zones>        A string containing any combination of: l r m 1 2
#                  (order does not matter)
#                  Zones resolve to:
#                     l  → left LED
#                     r  → right LED
#                     m  → middle LED
#                     1  → front LED f1
#                     2  → front LED f2
#                  Example: "lrm12", "m1", "r2", "l"
#
#   <effect>       One of the following keywords or numeric equivalents:
#                     0 | off | disable      → off
#                     1 | linear | rise      → linear rise
#                     2 | breath*            → breathing pattern
#                     3 | sniff              → "sniff" animation
#                     4 | static | on        → solid color
#                     5 | blink*1            → blink pattern 1
#                     6 | blink*2            → blink pattern 2
#                     7 | blink*3            → blink pattern 3
#
#   [color]        Hex RGB color (default: "FFFFFF")
#
#   [duration_ms]  Animation duration in milliseconds (default: 1000)
#
#   [cycles]       Number of animation cycles (default: 1)
#
#   [led trigger]  none battery-charging-or-full battery-charging battery-full 
#                  battery-charging-blink-full-solid usb-online ac-online 
#                  timer heartbeat gpio default-on mmc1 mmc0
#
#
# EXAMPLES:
#   rgb_led lrm breathe FF8800 2000 3 heartbeat
#   rgb_led m2 blink1 00FFAA
#   rgb_led 12 static
#   rgb_led r off
# ---------------------------------------------------------------------------

rgb_led() {
    log_message "Missing rgb_led function"
}

enable_or_disable_rgb() {
    log_message "Missing enable_or_disable_rgb function"
}

# Toggle the RGB LEDs between the configured colour and off. Device-specific
# (the LED sysfs paths differ per device), so implemented in the device file.
toggle_led() {
    log_message "Missing toggle_led function"
}

enter_sleep() {
    log_message "Missing enter_sleep function"
}

new_execution_loop() {
    log_message "Missing new_execution_loop function"
}

setup_for_retroarch(){
    log_message "Missing setup_for_retroarch function"
}

send_menu_button_to_retroarch() {
    log_message "Missing send_menu_button_to_retroarch function"
}

prepare_for_pyui_launch(){
    log_message "Missing prepare_for_pyui_launch function"
}

post_pyui_exit(){
    log_message "Missing post_pyui_exit function"
}

launch_startup_watchdogs(){
    log_message "No device-specific launch_startup_watchdogs function. Launching non-lid common watchdogs."
    launch_common_startup_watchdogs_v2
}

A30_notify_about_FW_update_if_needed(){
    log_message "Device is not an A30. Nothing to do for A30_notify_about_FW_update_if_needed." -v
}

check_if_fw_needs_update() {
    log_message "Missing check_if_fw_needs_update function"
}

take_screenshot() {
    log_message "Missing take_screenshot function"
}

get_sftp_service_name() {
    log_message "Missing get_sftp_service_name function"
}

# Which "first_boot_<key>" flag gates the firstboot lane for this device.
# Unlike its neighbours here this is a real default, not a missing-function stub:
# every platform needs a working value, and per-platform is the right answer for
# all but the Anbernic XX family, which overrides it to share one flag across
# models so moving a card between them does not re-run firstboot.
get_firstboot_key() {
    echo "$PLATFORM"
}

device_specific_wake_from_sleep() {
    log_message "Missing device_specific_wake_from_sleep function"
}

device_init() {
    log_message "Missing device_init function"
}

set_event_arg_for_idlemon() {
    log_message "Missing set_event_arg_for_idlemon function"
}

set_default_ra_hotkeys() {
    log_message "Missing set_default_ra_hotkeys function"
}

volume_down() {
    log_message "Missing volume_down function"
}

volume_up() {
    log_message "Missing volume_up function"
}

# System volume (why do we differentiate?)
get_current_volume() {
    log_message "Missing get_current_volume function"
}

# Config volume (We should normalize and not have 2 functions)
get_volume_level() {
    log_message "Missing get_volume_level function"
}

# Arg1: Sets the volume on a scale of 0-20
# Arg2: (optional) 'true' to save to config, anything else to not save
set_volume() {
    log_message "Missing set_volume function"
}

brightness_down() {
    log_message "Missing brightness_down function"
}

brightness_up() {
    log_message "Missing brightness_up function"
}

turn_off_screen() {
    log_message "Missing turn_off_screen function"
}

turn_on_screen() {
    log_message "Missing turn_on_screen function"
}

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
    log_message "Missing device_get_charging_status function"
}

device_get_battery_percent() {
    log_message "Missing device_get_battery_percent function"
}

device_enter_sleep() {
    log_message "Missing device_enter_sleep"
}

device_exit_sleep() {
    log_message "Missing device_exit_sleep"
}

device_lid_sensor_ready() {
    log_message "Missing device_lid_sensor_ready"
    return 1  # <-- sets exit status to 1 (failure)
}

# Returns 1 to indicate open, 0 otherwise
device_lid_open(){
    log_message "Missing device_lid_open"
    return 1
}

device_prepare_for_ports_run() {
    log_message "Missing device_prepare_for_ports_run function"
}

device_cleanup_after_ports_run() {
    log_message "Missing device_cleanup_after_ports_run function"
}

device_uses_pseudo_sleep() {
    log_message "Missing device_uses_pseudo_sleep function"
    echo "false"
}

device_woke_via_timer() {
    log_message "Missing device_woke_via_timer function"
    echo "false"
}

device_continue_sleep() {
    log_message "Missing device_continue_sleep function"
}

run_poweroff_cmd() {
    log_message "Missing run_poweroff_cmd -- using default of poweroff"
    poweroff
}

device_run_reboot_cmd() {
    log_message "Missing device_run_reboot_cmd -- using default of reboot"
    reboot
}

save_volume_to_config_file() {
    VOLUME_LV=$1

    # Update MainUI Config file
    sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOLUME_LV/" "$SYSTEM_JSON"
}

device_prepare_for_poweroff() {
    log_message "Missing device_prepare_for_poweroff function" -v
}

device_home_button_pressed() {
    log_message "Missing device_home_button_pressed function" -v
}

# Current position of the physical switch, in the same 1/0 convention
# /usr/trimui/bin/scene.sh uses: 1 = switch on, 0 = switch off.
#
# Echo nothing when the device cannot read it. apply-switch-action treats an
# empty answer as "do not touch the LEDs/radio at boot", which is the behaviour
# every device had before this existed - so a device with no reader is no worse
# off, it just does not get the boot-time apply.
device_get_switch_position() {
    echo ""
}

# True when the OS underneath spruce owns the radio end to end - association
# and DHCP both - so spruce must not start a wpa_supplicant or a DHCP client of
# its own alongside it. Default false: every device that manages WiFi through
# spruce keeps the existing behaviour.
device_manages_own_wifi() {
    return 1
}

device_wifi_power_on() { 
    log_message "Missing device_wifi_power_on function" -v
}

device_wifi_power_off() {
    log_message "Missing device_wifi_power_off function" -v
}

# Give a device a chance to bring its wireless interface back when it is not
# there. Default is to do nothing: on most devices the interface either exists
# or the radio is genuinely absent, and only SDIO parts that fail to enumerate
# need recovering.
device_ensure_wifi_interface() {
    return 0
}

device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    log_message "Missing device_system_handles_sdcard_unmount function, assuming it does" -v
    return 0
}

device_needs_strict_unmount() {
    # return 0 = true
    # return non-zero = false
    #
    # Whether save_poweroff_stage2.sh should take its strict unmount path:
    # resolve the mount point from /proc/mounts rather than guessing it from
    # cpuinfo, kill cwd/exe holders as well as fd holders, retry the umount, and
    # escalate the power command if init does not act on it.
    #
    # That path exists for the Anbernic XX under BaseOS, where the old code
    # matched nothing and unmounted nothing. Every other device already had a
    # shutdown that worked, and stage 2 is the last thing that runs before the
    # power is cut - the worst place in the tree to carry a change no one has
    # tested on that hardware. So it is off by default and each device opts in.
    return 1
}

device_write_default_asound_rc() {
    # Do these need to be unique per device? Don't have a way 
    # to test currently
    log_message "Missing device_write_default_asound_rc function" -v
}


device_get_hw_epoch() {
    # hwclock output like: Sat Jan 10 14:23:54 2026  0.000000 seconds
    hw_output=$(hwclock 2>/dev/null)
    set -- $hw_output
    MON=$2
    DAY=$3
    TIME=$4
    YEAR=$5
    
    # Convert month name to number
    case "$MON" in
        Jan) MM=01 ;;
        Feb) MM=02 ;;
        Mar) MM=03 ;;
        Apr) MM=04 ;;
        May) MM=05 ;;
        Jun) MM=06 ;;
        Jul) MM=07 ;;
        Aug) MM=08 ;;
        Sep) MM=09 ;;
        Oct) MM=10 ;;
        Nov) MM=11 ;;
        Dec) MM=12 ;;
        *) MM=00 ;;  # fallback
    esac

    HW_STR="${YEAR}-${MM}-${DAY} ${TIME}"

    # Convert to epoch seconds
    date -d "$HW_STR" +%s 2>/dev/null
}

device_extra_wifi_setup() {
    # Do these need to be unique per device? Don't have a way
    # to test currently
    log_message "Missing device_extra_wifi_setup function" -v
}

# Which DHCP client this device uses, and how to stop it.
#
# These exist because a device that needs a different client had nowhere to say
# so: enable_wifi hardcoded udhcpc, and the only per-device hook was
# device_extra_wifi_setup, which runs *in addition to* it rather than instead of
# it. The Anbernic XX line used that hook to run "dhclient wlan0" - a binary
# that is not installed on that platform - so it logged a DHCP client it never
# actually started, on top of the udhcpc that was really doing the work.
#
# The default is the udhcpc invocation enable_wifi used to run inline, so every
# device that does not override these behaves exactly as before. The "already
# running" guard lives in the hook rather than the caller because the check is
# client-specific.
device_start_dhcp_client() {
    pgrep -f "udhcpc.*wlan0" >/dev/null || udhcpc -i wlan0 -b -t 5 -T 3
}

device_stop_dhcp_client() {
    killall -9 udhcpc 2>/dev/null
}
