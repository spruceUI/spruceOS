#!/bin/sh
# Powkiddy RGB30 device functions.
#
# The host OS is MossySpruce (github.com/Sundownersport/MossySpruce), our fork
# of Moss, which is a fork of JELOS. That inheritance decides most of what is
# unusual here:
#
#   - systemd, glibc 2.38, a read-only squashfs root. Nothing under / is
#     writable at runtime; /storage and /storage/roms (TF2) are.
#   - Networking is connman, not a bare wpa_supplicant plus udhcpc. connman
#     owns association AND DHCP, so the DHCP hooks are deliberately empty
#     rather than starting a second client behind its back.
#   - TF2 is mounted by jelos-automount at /storage/roms and unmounted by
#     systemd on shutdown, so spruce must not fight it.

# The shared helpers every other 64-bit platform pulls in. Without these the
# boot log fills with "Missing <function>" and, more to the point, the CPU
# governor is never set and the watchdogs never launch.
#
# cpu_control_functions is entirely driven by the CPU_* variables in RGB30.cfg,
# so it needs no per-device code. legacy_display is not sourced: it drives the
# old framebuffer path, and this device is KMSDRM.
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"

device_init() {
    # Resolve the pad. MinUI's keymon.c reads
    # /sys/bus/platform/devices/singleadc-joypad/hp, so on this OS the driver
    # is singleadc-joypad without the rocknix- prefix. The Rocknix spelling is
    # still probed second so a Rocknix card does not silently bind nothing.
    for _node in \
        /dev/input/by-path/platform-singleadc-joypad-event-joystick \
        /dev/input/by-path/platform-rocknix-singleadc-joypad-event-joystick
    do
        if [ -e "$_node" ]; then
            export EVENT_PATH_READ_INPUTS_SPRUCE="$_node"
            export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$_node"
            export EVENT_PATH_SEND_TO_DRASTIC="$_node"
            log_message "RGB30: joypad at $_node"
            break
        fi
    done
    [ -e "$EVENT_PATH_READ_INPUTS_SPRUCE" ] || \
        log_message "RGB30: no singleadc joypad node found - controls will be dead"

    # The card is already mounted by jelos-automount; record what we got so a
    # wrong-card mount is obvious in the log rather than at first write.
    log_message "RGB30: TF2 is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT"

    resolve_key_event_node
    setup_mainui_alias
    add_spruce_system_user
}

# Fleet-standard SSH login, the same mechanism the Anbernic XX line uses:
# bind-mount an augmented passwd/shadow adding a root-equivalent "spruce" user,
# so this device logs in as spruce/happygaming like every spruce device.
# Ephemeral - re-applied each boot, gone on reboot, survives a Moss update.
#
# Two things differ from the XX version and were the whole SSH bring-up:
#   - Shell must be /usr/bin/bash. dropbear validates the login shell against
#     /etc/shells and rejects "invalid shell" BEFORE auth otherwise. Moss's
#     /etc/shells lists /usr/bin/bash and /usr/bin/sh - not /bin/sh or /bin/bash,
#     even though /bin/sh symlinks to bash. That refused every password and the
#     key, and is why root (shell /bin/sh) failed too.
#   - The password hash goes in the passwd field, not "x": this dropbear does not
#     consult /etc/shadow, so "x" there would never match. MD5 ($1$) crypt, which
#     it does verify.
add_spruce_system_user() {
    grep -q '^spruce:' /etc/passwd 2>/dev/null && return 0

    SP_HASH='$1$spruceos$iebg8jsgh1T2NBq8sw8KJ/'   # MD5 crypt of happygaming

    if cp /etc/passwd /tmp/spruce_passwd 2>/dev/null; then
        echo "spruce:${SP_HASH}:0:0:spruce:/storage:/usr/bin/bash" >> /tmp/spruce_passwd
        chmod 644 /tmp/spruce_passwd
        mount -o bind /tmp/spruce_passwd /etc/passwd
    fi
    if cp /etc/shadow /tmp/spruce_shadow 2>/dev/null; then
        echo "spruce:${SP_HASH}:19000:0:99999:7:::" >> /tmp/spruce_shadow
        chmod 600 /tmp/spruce_shadow
        mount -o bind /tmp/spruce_shadow /etc/shadow
    fi
    log_message "RGB30: spruce user added (spruce/happygaming)"
}

# Find the nodes carrying the power and volume keys, rather than guessing.
#
# The first attempt matched on device name and picked "rk805 pwrkey" - which is
# the power button, not volume. The real layout on this device is:
#   rk805 pwrkey => event0    adc-keys  => event1
#   gpio-keys    => event2    retrogame_joypad => event3
# and which of adc-keys or gpio-keys carries the volume rocker is not something
# a name tells you.
#
# So ask the kernel. Each node publishes its key capability bitmap, and
# KEY_VOLUMEDOWN(114)/KEY_VOLUMEUP(115) are either set or they are not.
node_reports_volume_keys() {
    _caps="/sys/class/input/$1/device/capabilities/key"
    [ -r "$_caps" ] || return 1
    awk '{
        s=""
        for (i=1; i<=NF; i++) { w=$i; if (i>1) { while (length(w)<16) w="0" w } s=s w }
        # Require BOTH KEY_VOLUMEDOWN(114) and KEY_VOLUMEUP(115). adc-keys on
        # this device declares only 114 (a phantom capability that never fires);
        # the real rocker is gpio-keys, which declares both. Matching on either
        # key picked the wrong node. A genuine volume rocker has up AND down.
        have=0
        for (k=114; k<=115; k++) {
            nib=int(k/4); bit=k%4; pos=length(s)-nib
            if (pos < 1) continue
            c=tolower(substr(s,pos,1))
            v=index("0123456789abcdef",c)-1
            if (v < 0) continue
            if (int(v/(2^bit))%2 == 1) have++
        }
        exit (have==2)?0:1
    }' "$_caps"
}

resolve_key_event_node() {
    _power=""
    _volume=""
    _seen=""

    for _dir in /sys/class/input/event*; do
        [ -e "$_dir" ] || continue
        _ev=$(basename "$_dir")
        _name=$(cat "$_dir/device/name" 2>/dev/null)
        _seen="$_seen ${_ev}:${_name}"

        if node_reports_volume_keys "$_ev" && [ -z "$_volume" ]; then
            _volume="/dev/input/$_ev"
        fi
        case "$_name" in
            *pwrkey*|*Power*|*power*) [ -z "$_power" ] && _power="/dev/input/$_ev" ;;
        esac
    done

    log_message "RGB30: input nodes:$_seen"

    if [ -n "$_volume" ] && [ -c "$_volume" ]; then
        export EVENT_PATH_VOLUME="$_volume"
        log_message "RGB30: volume keys on $_volume (kernel reports 114/115 there)"
    else
        log_message "RGB30: no node reports the volume keys - leaving $EVENT_PATH_VOLUME"
    fi

    if [ -n "$_power" ] && [ -c "$_power" ]; then
        export EVENT_PATH_POWER="$_power"
        log_message "RGB30: power key on $_power"
    fi

    # Persist the resolved nodes so every process gets them, not just this one.
    # The button watchdogs are launched as separate processes that re-source
    # RGB30.cfg fresh - an export here never reaches them, which is why the
    # volume watchdog was listening on the cfg's default node and the buttons
    # did nothing. RGB30.cfg reads this file back.
    {
        echo "EVENT_PATH_VOLUME='${EVENT_PATH_VOLUME}'"
        echo "EVENT_PATH_POWER='${EVENT_PATH_POWER}'"
    } > /tmp/rgb30_input_nodes 2>/dev/null
}

setup_mainui_alias() {
    MAINUI="/mnt/SDCARD/spruce/flip/bin/MainUI"
    PY="/mnt/SDCARD/spruce/flip/bin/python3.10"

    if [ ! -f "$PY" ]; then
        log_message "RGB30: $PY missing - PyUI cannot start"
        return 1
    fi

    # A plain copy survives a reboot on the FAT card, so only redo the work when
    # what is there is not already the interpreter.
    if [ -s "$MAINUI" ] &&        [ "$(stat -c%s "$MAINUI" 2>/dev/null)" = "$(stat -c%s "$PY" 2>/dev/null)" ]; then
        return 0
    fi

    touch "$MAINUI" 2>/dev/null
    mount -o bind "$PY" "$MAINUI" 2>/dev/null

    # Verify rather than trust: a failed bind is silent and leaves the empty
    # mount point in place.
    if [ ! -s "$MAINUI" ]; then
        log_message "RGB30: MainUI bind mount failed, copying interpreter instead"
        umount "$MAINUI" 2>/dev/null
        cp "$PY" "$MAINUI" || { log_message "RGB30: could not create MainUI"; return 1; }
        chmod +x "$MAINUI" 2>/dev/null
    fi
    log_message "RGB30: MainUI alias ready ($(stat -c%s "$MAINUI" 2>/dev/null) bytes)"
}

device_get_battery_percent() {
    cat "$BATTERY/capacity" 2>/dev/null || echo 0
}

# 'Discharging', 'Charging' or 'Full'. Mind the capitalization.
#
# Read the charger, not the battery. MinUI checks
# /sys/class/power_supply/ac/online on this device rather than battery/status,
# and the battery node's own status is not reliable on these RK handhelds.
device_get_charging_status() {
    if [ "$(cat /sys/class/power_supply/ac/online 2>/dev/null)" = "1" ]; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

# Headphone and HDMI state, both confirmed in MinUI's keymon.c. The headphone
# node also settles the driver name - singleadc-joypad, no rocknix- prefix.
device_headphones_connected() {
    [ "$(cat "$HEADPHONE_STATE_PATH" 2>/dev/null)" = "1" ]
}

device_hdmi_connected() {
    [ "$(cat "$HDMI_STATE_PATH" 2>/dev/null)" = "1" ]
}

  ###################
#####   NETWORK   #####
  ###################

# connman owns the radio end to end here - association and DHCP both - so
# spruce must not start a wpa_supplicant beside it. This is what stops
# enable_wifi from doing that; without it two daemons fight over wlan0 and the
# first boot log showed spruce launching wpa_supplicant on a connman system.
device_manages_own_wifi() {
    return 0
}

# connman is a daemon, not a per-connection process: it is already running and
# owns the radio. Toggling the interface is the right granularity here, and
# doing it through connman keeps its state machine in agreement with reality.
device_wifi_power_on() {
    connmanctl enable wifi >/dev/null 2>&1
}

device_wifi_power_off() {
    connmanctl disable wifi >/dev/null 2>&1
}

# connman runs its own DHCP. Starting udhcpc alongside it would give the
# interface two clients racing for the same lease - the mistake the Anbernic XX
# line made with dhclient. Deliberately empty, not unimplemented.
device_start_dhcp_client() {
    return 0
}

device_stop_dhcp_client() {
    return 0
}

  #################
#####   AUDIO   #####
  #################

# spruce defined no volume functions for this platform at all, so nothing ever
# touched the mixer and it stayed wherever Moss left it - which is full volume.
#
# This device is driven through 'Master' as a percentage, the way MinUI's
# msettings.c does it, not the Miyoo-style 'SPK Volume' control Flip.sh uses.

are_headphones_plugged_in() {
    [ "$(cat "$HEADPHONE_STATE_PATH" 2>/dev/null)" = "1" ]
}

# The path VALUES are inverted on this hardware: "HP" selects the speaker and
# "SPK" selects headphones. Confirmed twice - a live RGB30's own 002-audio_path
# and MinUI's msettings.c agree. AUDIO_PATH_SPK/HP in RGB30.cfg already hold
# the corrected values, so read them rather than writing the names here.
apply_playback_path() {
    if are_headphones_plugged_in; then
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_HP" 2>/dev/null
    else
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_SPK" 2>/dev/null
    fi
}

# buttons_watchdog.sh calls volume_up/volume_down by name, and reads the
# current level from the system json rather than from the mixer - so the two
# have to agree, which is why set_volume saves to config by default.
get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON" 2>/dev/null || echo 0
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -lt 20 ]; then
        set_volume "$(( VOLUME_LV + 1 ))"
    fi
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -gt 0 ]; then
        set_volume "$(( VOLUME_LV - 1 ))"
    fi
}

get_current_volume() {
    amixer get 'Master' 2>/dev/null | sed -n 's/.*\[\([0-9]\+\)%\].*/\1/p' | head -1
}

set_volume() {
    VOLUME_LV="$1"
    SAVE_TO_CONFIG="${2:-true}"

    VOLUME_PCT=$(( VOLUME_LV * 5 ))
    [ "$VOLUME_PCT" -gt 100 ] && VOLUME_PCT=100
    [ "$VOLUME_PCT" -lt 0 ] && VOLUME_PCT=0

    # Level before path. Switching output while the old level is still applied
    # is what produces the burst the Flip had to be fixed for.
    amixer -q sset -M 'Master' "${VOLUME_PCT}%" 2>/dev/null
    apply_playback_path
    log_message "RGB30: volume ${VOLUME_LV}/20 (${VOLUME_PCT}%)"

    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$VOLUME_LV" 2>/dev/null
    fi
}

  #########################
#####   IN-GAME MENU   #####
  #########################

# The home button (L3) opening the emulator menu in-game goes through
# common64bit's send_menu_button_to_retroarch, which pipes MENU_TOGGLE to
# RetroArch's UDP command port with spruce's bundled netcat. That netcat's
# hardcoded ELF loader path does not exist on Moss, so it dies with "No such
# file or directory" and the menu never opens. Moss ships its own BusyBox nc,
# which needs no loader - use it.
send_menu_button_to_retroarch() {
    if pgrep -f "ra64.universal|ra32.universal|retroarch" >/dev/null; then
        echo "MENU_TOGGLE" | /usr/bin/nc -u -w1 127.0.0.1 55355
    fi
}

  ####################
#####   SHUTDOWN   #####
  ####################

# systemd unmounts /storage/roms on the way down, and it does it correctly.
device_system_handles_sdcard_unmount() {
    return 0
}

# The strict unmount path exists for BaseOS, where init raced spruce for the
# card. systemd does not, so leave it off.
device_needs_strict_unmount() {
    return 1
}

device_run_reboot_cmd() {
    systemctl reboot
}

device_prepare_for_poweroff() {
    sync
}
