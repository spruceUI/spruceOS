#!/bin/bash

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

get_config_path() {
    echo "$SYSTEM_JSON"
}

###############################################################################
WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

device_exit_sleep() {
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down 
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_READ_INPUTS_SPRUCE
}


has_lid() {
    # BaseOS has no vendor partition, so board.ini is gone. Its build target is
    # the same information: every clamshell target ends in "sp" (rg34xxsp,
    # rg35xxsp, rgsp).
    if [ -n "$SPRUCE_BASEOS" ]; then
        case "$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)" in
            *sp) return 0 ;;
            *)   return 1 ;;
        esac
    fi

    BOARD="$(cat /mnt/vendor/oem/board.ini)"
    case "$BOARD" in
        *xxSP*) return 0 ;;
        *)    return 1 ;;
    esac
}

launch_startup_watchdogs(){
    /bin/bash /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &
    /bin/bash /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
    /bin/bash /mnt/SDCARD/spruce/scripts/power_button_watchdog_v2.sh &

    if has_lid >/dev/null; then
        /bin/bash /mnt/SDCARD/spruce/scripts/lid_watchdog_v2.sh &
    fi
}

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}



take_screenshot() {
    log_message "Unable to doso on 34xxsp currently"
}

runtime_mounts_anbernic_34xxsp() {

    #mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    #mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    #mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &

    # Half of spruce finds the UI with `pgrep MainUI` / `killall MainUI`, so the
    # interpreter has to carry that name. On stock that is a symlink to the
    # system python; under BaseOS there is no system python, so alias the
    # bundled one the same way Flip.sh does.
    if [ -n "$SPRUCE_BASEOS" ]; then
        MAINUI="/mnt/SDCARD/spruce/flip/bin/MainUI"
        touch "$MAINUI"
        # -o bind, not --bind: BaseOS is BusyBox and its mount does not take the
        # util-linux long option stock Ubuntu accepted. A failed bind here is
        # silent and leaves the empty mount point behind, so PyUI execs a 0-byte
        # file and principal.sh spins forever on a blank screen. Verify, and fall
        # back to a plain copy rather than trusting the mount.
        mount -o bind /mnt/SDCARD/spruce/flip/bin/python3.10 "$MAINUI" 2>/dev/null
        if [ ! -s "$MAINUI" ]; then
            log_message "MainUI bind mount failed, copying interpreter instead"
            umount "$MAINUI" 2>/dev/null
            cp /mnt/SDCARD/spruce/flip/bin/python3.10 "$MAINUI"
            chmod +x "$MAINUI"
        fi
    else
        ln -s /usr/bin/python3 /usr/bin/MainUI
    fi

    # Stock lets us borrow Anbernic's own RetroArch assets off the vendor
    # partition. BaseOS drops that partition; skip rather than fail the mount.
    if [ -d /mnt/vendor/deep/retro/retroarch-1.20 ]; then
        mount --bind /mnt/vendor/deep/retro/retroarch-1.20 /mnt/sdcard/RetroArch/retroarch
    fi
}

device_init() {
    # launch_startup_watchdogs runs every watchdog through /bin/bash. Stock
    # Anbernic is Ubuntu and has one; BaseOS is BusyBox and does not, so the
    # watchdogs would all fail silently and take the power and home buttons with
    # them. Same static aarch64 bash the TrimUI devices drop in for this reason.
    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi

    runtime_mounts_anbernic_34xxsp

    [ -n "$SPRUCE_BASEOS" ] && add_spruce_ssh_user

    # BaseOS composes its own adb gadget and binds the UDC during boot. Starting
    # ours as well would leave two daemons fighting over one controller.
    if [ -z "$SPRUCE_BASEOS" ]; then
        {
            sleep 10
            /mnt/SDCARD/anbernic_adbd/run_adbd.sh &
        } &
    fi
}

# BaseOS ships only a root user (its dropbear is root/root), so the fleet-standard
# spruce/happygaming SSH login does not exist here. Rather than fight BaseOS's own
# dropbear or edit its rootfs, bind-mount an augmented passwd/shadow that keeps
# every existing line (root untouched) and adds a root-equivalent "spruce" user.
# Ephemeral - re-applied each boot, gone on reboot, survives BaseOS updates.
add_spruce_ssh_user() {
    grep -q '^spruce:' /etc/passwd 2>/dev/null && return 0

    SP_HASH='$6$spruceos00$.nwqRlVkLe.wmkXcEHXcu127ZFxpFQ.8JDbdh4CRd.FbF5biVcIl9qeE9T6QNAbbJaFKp3MLUwlaPUN0alXcl.'
    cp /etc/passwd /tmp/spruce_passwd || return 0
    cp /etc/shadow /tmp/spruce_shadow || return 0
    echo 'spruce:x:0:0:spruce:/root:/bin/sh' >> /tmp/spruce_passwd
    echo "spruce:${SP_HASH}:19000:0:99999:7:::" >> /tmp/spruce_shadow
    chmod 644 /tmp/spruce_passwd
    chmod 600 /tmp/spruce_shadow
    mount -o bind /tmp/spruce_passwd /etc/passwd
    mount -o bind /tmp/spruce_shadow /etc/shadow
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e /dev/input/event1" # is this right?
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    # Update RetroArch config with default values
    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"4\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"9\"" \
        "input_menu_toggle = \"escape\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_save_state_btn = \"10\"" \
        "input_screenshot_btn = \"1\"" \
        "input_shader_toggle_btn = \"11\"" \
        "input_state_slot_decrease_btn = \"13\"" \
        "input_state_slot_increase_btn = \"14\"" \
        "input_toggle_slowmotion_axis = \"+4\"" \
        "input_toggle_fast_forward_axis = \"+5\""

}

new_execution_loop() {
    log_message "new_execution_loop unneeded on this device" -v
}

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    return 0
}

set_volume() {
    new_vol="${1:-0}"        # default to mute
    SAVE_TO_CONFIG="${2:-true}"

    # Clamp 0–20
    [ "$new_vol" -lt 0 ] && new_vol=0
    [ "$new_vol" -gt 20 ] && new_vol=20

    # Map 0–20 -> 0–31 (rounded)
    system_volume=$(( (new_vol * 31 + 10) / 20 ))

    amixer -q set 'lineout volume' "$system_volume"

    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol' "$SYSTEM_JSON")

        if [ "$current_volume" -ne "$new_vol" ]; then
            save_volume_to_config_file "$new_vol"

            sed 's/"vol":[[:space:]]*[0-9]\+/"vol": '"$new_vol"'/' \
                "$SYSTEM_JSON" > "$SYSTEM_JSON.tmp" && mv "$SYSTEM_JSON.tmp" "$SYSTEM_JSON"
        fi
    fi
}

set_volume_delta() {
    delta="$1"

    current=$(get_volume_level)
    [ -z "$current" ] && current=0

    new=$((current + delta))

    # Clamp 0–20
    [ "$new" -lt 0 ] && new=0
    [ "$new" -gt 20 ] && new=20

    set_volume "$new"
}

volume_up() {
    set_volume_delta 1
}

volume_down() {
    set_volume_delta -1
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}


send_menu_button_to_retroarch() {
    if pgrep "ra64.universal" >/dev/null || pgrep "ra32.universal" >/dev/null; then
        echo "MENU_TOGGLE" |  /lib/ld-linux-aarch64.so.1 /mnt/SDCARD/spruce/bin64/netcat -u -w0.1 127.0.0.1 55355
    fi
}

device_get_hw_epoch() {
    # Capture the raw output
    hw_output=$(hwclock 2>/dev/null)
    
    # If hw_output is empty, the command failed
    [ -z "$hw_output" ] && return 1

    # 'date' is smart enough to handle the ISO-8601 format 
    # and even the sub-seconds automatically.
    date -d "$hw_output" +%s 2>/dev/null
}

device_lid_sensor_ready() {
    [ -e "/sys/class/power_supply/axp2202-battery/hallkey" ]
}

device_lid_open() {
    head -c 1 "/sys/class/power_supply/axp2202-battery/hallkey" 2>/dev/null || echo "1"
}

setup_for_retroarch(){
	#RA_DIR="/mnt/vendor/deep/retro"
    #export RA_BIN="retroarch"
    #export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
    #cp /mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG28XX.cfg /.config/retroarch/retroarch.cfg

    if [ "$RA_BIN" = "ra32.universal" ]; then
        export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
        export LD_LIBRARY_PATH="/usr/lib32:$LD_LIBRARY_PATH"
    else
        export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores64"
    fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"
}

device_extra_wifi_setup(){
    dhclient wlan0
    log_message "Starting dhclient"
}
