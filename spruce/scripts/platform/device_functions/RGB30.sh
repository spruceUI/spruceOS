#!/bin/sh
# Powkiddy RGB30 device functions.
#
# The host OS is dArkMoss (github.com/spruceUI/dArkMoss), our fork of dArkOS,
# which is Debian trixie. That decides most of what is unusual here:
#
#   - systemd and a full Debian userland on a mutable ext4 root.
#   - Networking is NetworkManager, not a bare wpa_supplicant plus udhcpc.
#     nmcli owns association AND DHCP, so the DHCP hooks are deliberately empty
#     rather than starting a second client behind its back.
#   - TF2 is mounted at /mnt/SDCARD by the base image's mount-spruce.sh and
#     unmounted by systemd on shutdown, so spruce must not fight it.

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

    # The card is already mounted by the base image; record what we got so a
    # wrong-card mount is obvious in the log rather than at first write.
    log_message "RGB30: TF2 is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT"

    resolve_key_event_node
    setup_mainui_alias

    # Network first so the device is reachable, then a snapshot of the machine
    # for whenever something here next goes wrong.
    rgb30_wifi_up
    rgb30_debug_dump
}

# spruce's SSH toggle drives the base OS's sshd, not dropbear.
#
# dropbear cannot have port 22 here - Debian's own sshd owns it - and there is
# no reason to fight a daemon that already works. Anything other than
# "dropbearmulti" sends start_ssh_process and stop_ssh_process down their
# systemctl branch.
#
# "ssh", not "sshd": that is what Debian calls the unit. It does declare
# Alias=sshd.service, but systemd only creates that alias when the unit is
# enabled, and enabling it conflicts with the ssh.socket that actually serves
# port 22 on Debian 13.
#
# The spruce login itself (spruce/happygaming, root-equivalent) is baked into
# the image by setup_spruce_handoff-rk3566.sh. It used to be fabricated here at
# boot by bind-mounting an augmented /etc/passwd and /etc/shadow, which is what
# the platforms whose base images we do not own still have to do.
get_ssh_service_name() {
    echo "ssh"
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
# touched the mixer and it stayed wherever the base left it - full volume.
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
# hardcoded ELF loader path does not exist on this base, so it dies with "No
# such file or directory" and the menu never opens. The base ships BusyBox nc,
# which needs no loader - use it.
send_menu_button_to_retroarch() {
    if pgrep -f "ra64.universal|ra32.universal|retroarch" >/dev/null; then
        echo "MENU_TOGGLE" | /usr/bin/nc -u -w1 127.0.0.1 55355
    fi
}

  ####################
#####   SHUTDOWN   #####
  ####################

# systemd unmounts /mnt/SDCARD on the way down, and it does it correctly.
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

# Poweroff uses a DIFFERENTLY NAMED hook than reboot: the base default is
# run_poweroff_cmd (no device_ prefix), while reboot is device_run_reboot_cmd.
# Miss that and poweroff silently falls through to the base's bare `poweroff`,
# which does not go through systemd's clean unmount. That leaves TF2's FAT dirty,
# and leaves the FAT dirty. Route poweroff through systemd, the same as
# reboot, so /mnt/SDCARD is unmounted cleanly.
run_poweroff_cmd() {
    systemctl poweroff
}

device_prepare_for_poweroff() {
    sync
}

# ---------------------------------------------------------------------------
# dArkMoss support
# ---------------------------------------------------------------------------
#
# PyUI could not open a window on this base until 2026-08-26. SDL picks its
# EGL config from gl_config.profile_mask, which defaults to desktop GL, and
# this Mali G52 blob advertises no desktop GL config at all - all 64 report
# GLES only. Fixed in PyUI by asking for a GLES config; see
# Device.wants_gles_context() and devices/rgb30/rgb30.py.
#
# Ruled out along the way, so nobody re-runs them: DRM master contention
# (nothing ever holds /dev/dri, and plymouth is not installed), the SDL
# library stack (base and bundled fail and succeed alike), GBM formats (all
# five SDL uses create surfaces fine), and the EGL entry point (SDL had a
# display the whole time). rgb30_gbm_probe.py is kept for the next time
# something here goes dark - run it by hand, it is not part of boot.

RGB30_DEBUG_LOG="/mnt/SDCARD/Saves/spruce/rgb30_debug.log"

# Which processes have a DRM device open, without depending on fuser or lsof
# being installed. Prints "pid (cmdline) -> /dev/dri/..." per open handle.
rgb30_drm_holders() {
    for _fd in /proc/[0-9]*/fd/*; do
        _tgt="$(readlink "$_fd" 2>/dev/null)" || continue
        case "$_tgt" in
            /dev/dri/*)
                _pid="${_fd#/proc/}"
                _pid="${_pid%%/*}"
                _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
                [ -z "$_cmd" ] && _cmd="[$(cat "/proc/$_pid/comm" 2>/dev/null)]"
                echo "  pid $_pid ($_cmd) -> $_tgt"
                ;;
        esac
    done
}

# Everything we would otherwise be swapping cards to find out.
rgb30_debug_dump() {
    {
        echo "================ $(date 2>/dev/null) ================"
        echo "--- kernel cmdline (is 'splash' set?)"
        cat /proc/cmdline 2>&1
        echo "--- os-release"
        grep -E "^(OS_NAME|OS_VERSION|PRETTY_NAME)=" /etc/os-release 2>&1
        echo "--- /dev/dri"
        ls -l /dev/dri/ 2>&1
        echo "--- drm connectors"
        for _s in /sys/class/drm/*/status; do
            [ -r "$_s" ] && echo "  $_s = $(cat "$_s" 2>/dev/null)"
        done
        echo "--- who holds /dev/dri"
        _h="$(rgb30_drm_holders)"
        [ -n "$_h" ] && echo "$_h" || echo "  (nobody)"
        echo "--- active console / vt"
        cat /sys/class/tty/console/active 2>&1
        command -v fgconsole >/dev/null 2>&1 && fgconsole 2>&1
        echo "--- plymouth"
        if command -v plymouth >/dev/null 2>&1; then
            plymouth --ping >/dev/null 2>&1 && echo "  running" || echo "  installed, not running"
        else
            echo "  not installed"
        fi
        echo "--- failed units"
        command -v systemctl >/dev/null 2>&1 && systemctl list-units --failed --no-pager --no-legend 2>&1 | head -20
        echo "--- SD_DEV / mounts (the unresolved SD_DEV problem)"
        echo "  SD_DEV=${SD_DEV:-<unresolved>}  SD_MOUNTPOINT=$SD_MOUNTPOINT"
        mount 2>&1 | grep -E "SDCARD|roms|mmcblk" 
        echo "--- network (NetworkManager)"
        if command -v ip >/dev/null 2>&1; then
            ip -4 -o addr show 2>&1 | grep -v " lo " || echo "  no IPv4 address - SSH will be unreachable"
        else
            ifconfig 2>&1 | grep -E "inet |^[a-z]" | head
        fi
        if command -v nmcli >/dev/null 2>&1; then
            echo "  nmcli state: $(nmcli -t -f STATE general 2>&1)"
            echo "  active: $(nmcli -t -f NAME,DEVICE connection show --active 2>&1 | tr '\n' ' ')"
        fi
        echo "--- is anything listening on 22"
        (netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null) | grep -E ":22[[:space:]]" || echo "  nothing on 22 yet"
        echo "--- graphics libs present on the base"
        ls -l /usr/lib/aarch64-linux-gnu/libEGL.so* \
              /usr/lib/aarch64-linux-gnu/libgbm.so* \
              /usr/lib/aarch64-linux-gnu/libmali* 2>&1 | head -10
    } >> "$RGB30_DEBUG_LOG" 2>&1
}

# Force SSH up regardless of the Network Settings toggle, for bring-up only.
#
# networkservices.sh already starts SSH from the enableSSH setting at boot, and
# now that get_ssh_service_name reports the right unit it works properly here -
# so this must NOT run unconditionally, or it would quietly override a user who
# turned SSH off.
#
# It stays behind a flag because the one time a shell is worth most is when the
# frontend is crash-looping and the settings screen cannot be reached, which is
# exactly how this platform was brought up. To arm it:
#
#     touch /mnt/SDCARD/spruce/flags/rgb30_force_ssh
#
# Start the base OS's own sshd.
#
# dArkOS ships SSH off - its Enable/Disable Remote Services tools are just
# `systemctl start|stop ssh.service` - so port 22 is refused on a normal boot.
# spruce's dropbear cannot substitute: it tried, found the port taken on the
# one boot where sshd happened to be up, and correctly refused to fight it.
#
# Starting rather than enabling: enabling writes to TF1, and a diagnostic
# should not quietly change the base image. This costs one systemctl call per
# boot and leaves the image as it was.
rgb30_ssh_up() {
    [ -e /mnt/SDCARD/spruce/flags/rgb30_force_ssh ] || return 0

    command -v systemctl >/dev/null 2>&1 || return 0

    if systemctl is-active --quiet "$(get_ssh_service_name)" 2>/dev/null; then
        log_message "RGB30: base sshd already running"
        return 0
    fi

    # A daemon that has never run has no host keys, and sshd exits rather than
    # generating them itself.
    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -A >/dev/null 2>&1
    fi

    if systemctl start "$(get_ssh_service_name)" >/dev/null 2>&1; then
        log_message "RGB30: started base sshd"
    else
        log_message "RGB30: could not start $(get_ssh_service_name)"
    fi
}

# Bring WiFi up through NetworkManager, which is what this base actually runs.
#
# The base OS handles the radio; all spruce has to do is hand nmcli a network. Credentials live in Saves/spruce/rgb30_wifi.conf on
# the card and never enter the repo.
#
# This matters beyond convenience: dArkMoss already runs Debian's ssh.service
# on :22, so a network is the only thing standing between us and a shell on the
# device - and without one, every idea costs a card swap.
rgb30_wifi_up() {
    _conf="/mnt/SDCARD/Saves/spruce/rgb30_wifi.conf"

    [ -f "$_conf" ] || return 0
    command -v nmcli >/dev/null 2>&1 || return 0

    _ssid="$(sed -n 's/^SSID=//p' "$_conf" | head -1)"
    _psk="$(sed -n 's/^PSK=//p' "$_conf" | head -1)"

    if [ -z "$_ssid" ] || [ -z "$_psk" ]; then
        log_message "RGB30: wifi config present but incomplete"
        return 0
    fi

    if nmcli -t -f STATE general 2>/dev/null | grep -q "^connected"; then
        log_message "RGB30: already connected"
        return 0
    fi

    (
        nmcli radio wifi on >/dev/null 2>&1

        # The radio needs a moment before a scan returns anything, and
        # "device wifi connect" only sees networks already in the scan list -
        # which is why a boot that worked once can fail the next time.
        _try=0
        while [ "$_try" -lt 20 ]; do
            nmcli device wifi rescan >/dev/null 2>&1

            # A previous successful connect leaves a saved profile; bringing
            # that up is cheaper and more reliable than re-associating from
            # scratch with the credentials.
            if nmcli connection up id "$_ssid" >/dev/null 2>&1 ||
               nmcli device wifi connect "$_ssid" password "$_psk" >/dev/null 2>&1; then
                # nmcli returns as soon as the association succeeds, which is
                # before DHCP has handed out an address - asking right away
                # reports "connected" with nothing to connect to.
                _addr=""
                _wait=0

                while [ "$_wait" -lt 20 ]; do
                    _addr="$(ip -4 -o addr show scope global 2>/dev/null |
                        awk '{print $4}' | cut -d/ -f1 | head -1)"
                    [ -n "$_addr" ] && break
                    _wait=$((_wait + 1))
                    sleep 1
                done

                if [ -n "$_addr" ]; then
                    rgb30_ssh_up
                    log_message "RGB30: wifi up at $_addr - ssh spruce@$_addr"
                    # Also drop it on the card, so the address survives to the
                    # next time the card is in the PC.
                    printf '%s\n' "$_addr" > /mnt/SDCARD/Saves/spruce/rgb30_ip.txt 2>/dev/null
                else
                    log_message "RGB30: wifi associated but no DHCP lease after 20s"
                fi

                exit 0
            fi

            _try=$((_try + 1))
            sleep 3
        done

        # Deliberately not logging the nmcli error verbatim: it echoes the
        # arguments it was given.
        log_message "RGB30: wifi did not connect after 60s"
    ) &
}
