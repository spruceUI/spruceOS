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

# The XX line has no rumble GPIO, so utils/rumble.sh's rumble_gpio is not usable
# here - see RUMBLE_GPIO in AnbernicXXCommon.cfg. The motor is driven through
# evdev force feedback on the pad, which is the Pixel2's approach, and this
# keeps that call shape: rumble <device> <intensity> <duration-ms>.
#
# The magnitudes below are STARTING VALUES, not tuned ones. Measured on an RG SP:
# 0x1000 at 200ms and 0x2000 at 150ms could not be felt at all, while 0x8000 and
# 0xFFFF both could - so this motor has a floor somewhere above 0x2000, and the
# Pixel2's Weak of 0x2000 would read as "rumble is broken" here. All three values
# are therefore at or above a magnitude confirmed to work, so no setting can
# silently do nothing.
#
# Duration was a poor intensity lever in testing - 50ms felt very weak and 150ms
# normal, but 250ms was reported weaker than 150ms, so perceived strength does
# not track on-time cleanly on this motor. Intensity is expressed through
# magnitude instead, as on every other device. Retune freely: these are numbers
# in a shell script and need no rebuild.
vibrate() {
    duration=150
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    # Arguments in any order, matching the other platforms.
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
        "Weak")   intensity=0x8000 ;;
        "Medium") intensity=0xC000 ;;
        "Strong") intensity=0xFFFF ;;
    esac

    [ -x /mnt/SDCARD/spruce/bin64/rumble ] || return 0
    /mnt/SDCARD/spruce/bin64/rumble "$EVENT_PATH_READ_INPUTS_SPRUCE" "$intensity" "$duration"
}

get_config_path() {
    echo "$SYSTEM_JSON"
}

# One firstboot flag for the whole XX family rather than one per model. These
# devices differ only in screen and shell, so a card moved from an RG SP to a
# CubeXX has nothing left to set up - re-running the lane would only replay the
# onboarding screens and re-extract packages it already extracted.
get_firstboot_key() {
    echo "AnbernicXX"
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
    case "$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)" in
        *sp) return 0 ;;
        *)   return 1 ;;
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

    add_spruce_system_user
    shield_baseos_session
}

# Stop BaseOS's respawned session from re-mounting the card during shutdown.
#
# /etc/inittab has `::respawn:/sbin/nextui-session`, so the moment save_poweroff
# kills the frontend, init starts another one. That script's job includes
# mounting the card if it finds it unmounted - its own comment says the retry
# covers "hot re-insertion after an unmount" - and it cannot tell a deliberate
# shutdown unmount from a yanked card:
#
#     mount -t vfat -o rw,utf8,noatime,shortname=mixed "$dev" "$SD"
#
# Mounting read-write sets the FAT dirty bit. So stage 2 would unmount the card
# cleanly and a second later BaseOS would helpfully mount it straight back, and
# every boot still opened with "Volume was not properly unmounted". Traced end to
# end: clean umount OK, then a session start in the same second.
#
# Bind a shim over it that steps aside while a shutdown is in progress. Same
# technique spruce already uses for /etc/passwd and MainUI, and ephemeral for the
# same reason: nothing is written to BaseOS's rootfs, a BaseOS update can neither
# inherit nor break it, and a reboot removes it entirely. If anything here fails
# we simply leave BaseOS's own script in place.
shield_baseos_session() {
    [ -f /sbin/nextui-session ] || return 0
    # Already shielded - device_init can run more than once, and binding twice
    # stacks mounts. Match on the name alone: /sbin is a symlink to /usr/sbin
    # here, and /proc/mounts reports the resolved path, so testing for the
    # literal "/sbin/..." finds nothing and happily binds again.
    grep -q "nextui-session" /proc/mounts 2>/dev/null && return 0

    cp /sbin/nextui-session /tmp/nextui-session.real 2>/dev/null || return 0
    chmod +x /tmp/nextui-session.real 2>/dev/null

    cat > /tmp/nextui-session.shim <<'SHIM'
#!/bin/sh
# spruce shim over BaseOS's frontend session. Bind-mounted, never installed.
# While a shutdown is in progress the real session must not run: it mounts the
# SD card read-write when it finds it unmounted, which re-dirties the filesystem
# save_poweroff.sh has just unmounted cleanly. The sleep keeps init's respawn
# from becoming a hot loop for the few seconds before the power goes.
if [ -e /tmp/shutting_down.lock ]; then
    sleep 5
    exit 0
fi
exec /tmp/nextui-session.real "$@"
SHIM
    chmod +x /tmp/nextui-session.shim 2>/dev/null

    if mount -o bind /tmp/nextui-session.shim /sbin/nextui-session 2>/dev/null; then
        log_message "Shielded BaseOS session script against shutdown remounts"
    else
        log_message "Could not shield BaseOS session script; card may be remounted during shutdown"
    fi
}

# Create the spruce system account. BaseOS ships only a root user, so the
# fleet-standard "spruce" account does not exist here - and /etc/passwd lives on
# the BaseOS rootfs, which is not ours to edit. Bind-mount an augmented
# passwd/shadow instead, keeping every existing line (root untouched) and adding
# a root-equivalent "spruce" user. Ephemeral - re-applied each boot, gone on
# reboot, survives BaseOS updates.
#
# NOT just an SSH concern, despite where it started:
#   - dropbear authenticates via /etc/passwd and /etc/shadow, so this is what
#     makes spruce/happygaming work. That is true of spruce's own dropbearmulti
#     just as it was of BaseOS's dropbear - taking port 22 off BaseOS
#     (stop_foreign_ssh in sshFunctions.sh) changed the daemon, not where
#     credentials are read from.
#   - Samba needs it too: start_samba_process runs `smbpasswd -a spruce`, which
#     attaches an SMB password to an *existing* Unix account and fails without one.
# Removing this would leave root/root as the only login on the XX line and break
# file sharing, so it is load-bearing rather than leftover scaffolding.
add_spruce_system_user() {
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
    #
    # Stock Anbernic's userland unmounts the card properly. BaseOS does not, and
    # cannot as sequenced: busybox init runs its ::shutdown: action - rcK, which
    # does `umount -a -r` - BEFORE it kills anything, while a dozen processes are
    # still executing from the card. The unmount always fails, and every boot
    # opens with:
    #
    #   FAT-fs (mmcblk1p1): Volume was not properly unmounted.
    #
    # Returning false routes shutdown through unmount_all + save_poweroff_stage2,
    # which copies itself to /tmp, drops the card from PATH and LD_LIBRARY_PATH,
    # kills everything still holding it, and unmounts it properly.
    #
    # Safe here specifically because these are two-card devices: the rootfs is on
    # TF1 (mmcblk0) and spruce is on TF2 (mmcblk1), so unmounting spruce's card
    # cannot strand the OS - init, /bin and /usr/bin all keep running from TF1.
    return 1
}

device_needs_strict_unmount() {
    # return 0 = true
    # return non-zero = false
    #
    # The strict stage 2 path was written for this device and verified only
    # here. It pairs with device_system_handles_sdcard_unmount above: the same
    # BaseOS condition that routes shutdown through stage 2 is what makes the
    # strict path necessary, since /mnt/SDCARD is a symlink there and the old
    # cpuinfo guess matched no mount line at all.
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
    # Every RetroArch binary this device can launch has to be listed here or the
    # home button silently does nothing in-game. ra64.h700 is the BaseOS default.
    if pgrep "ra64.universal" >/dev/null || pgrep "ra32.universal" >/dev/null \
       || pgrep "ra64.h700" >/dev/null || pgrep "ra32.h700" >/dev/null; then
        echo "MENU_TOGGLE" |  /lib/ld-linux-aarch64.so.1 /mnt/SDCARD/spruce/bin64/netcat -u -w0.1 127.0.0.1 55355
    fi
}

# device_get_hw_epoch is deliberately NOT overridden here - device.sh's generic
# version is correct and this one was not. It assumed `date -d` could parse
# hwclock's output, but hwclock emits ctime style:
#
#     Thu Aug 20 02:28:56 2026  0.000000 seconds
#
# not the ISO-8601 its comment claimed, and busybox `date -d` cannot read that.
# It therefore returned an empty string on every call. That made save_sleep_info
# log "ERROR: Unable to read hwclock" and fail, so device_enter_sleep returned
# before ever calling trigger_device_sleep - the device never attempted to
# suspend at all. Closing the lid looked like it did nothing, when in fact the
# hall sensor, the lid watchdog and sleep_helper were all working correctly and
# the sleep was aborting one step short of the suspend.
#
# device.sh splits the fields by hand for exactly this reason, and works here.

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

    # Match on the arch prefix rather than one exact filename: ra32.h700 is a
    # 32-bit binary too, and the old equality test would have handed it the
    # 64-bit core directory and no 32-bit library path at all.
    case "$RA_BIN" in
        ra32.*)
            export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
            if [ -n "$SPRUCE_BASEOS" ]; then
                # BaseOS has no /usr/lib32 - its harvest carries only the armhf
                # loader and libc (enough for the vendor bluetooth binary). The
                # rest of the 32-bit closure ships with spruce; see the
                # PROVENANCE note in spruce/h700/lib32.
                export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/h700/lib32:$LD_LIBRARY_PATH"
            else
                # Stock Anbernic is Ubuntu with a full 32-bit multilib.
                export LD_LIBRARY_PATH="/usr/lib32:$LD_LIBRARY_PATH"
            fi
            ;;
        *)
            export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores64"
            ;;
    esac

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
