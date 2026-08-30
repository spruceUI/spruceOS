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
# so it needs no per-device code. legacy_display supplies display and
# display_kill. display_kill is the one that earns its keep - principal.sh calls
# it on every pass through the menu loop to clear strays, and without the source
# it would hit device.sh's log-only stub.
#
# display itself will NOT render on this device, and that is worth knowing
# before someone spends an afternoon on it. It runs bin64/display_text.elf,
# which calls SDL_CreateWindow and SDL_CreateRenderer and never touches
# SDL_GL_SetAttribute. On KMSDRM, SDL takes its EGL config from
# gl_config.profile_mask, which defaults to desktop GL, and this Mali G52 blob
# advertises no desktop GL config at all - the exact wall PyUI hit until
# wants_gles_context() was added. So display_text.elf dies at CreateWindow with
# "Can't window GBM/EGL surfaces" and there is no env knob for the profile mask;
# it needs a rebuild that asks for ES.
#
# Sourcing anyway: the only caller of display on this device is m3u_generator's
# progress screen, which carries on without it, and the alternative is losing a
# working display_kill to keep a broken display honest. Fix it in the binary,
# not here.
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
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

# NetworkManager owns the radio end to end here - association and DHCP both -
# so spruce must not start a wpa_supplicant beside it. This is what stops
# enable_wifi from doing that; without it two daemons fight over wlan0 and the
# first boot log showed spruce launching wpa_supplicant on top of the base's.
device_manages_own_wifi() {
    return 0
}

# NetworkManager is a daemon, not a per-connection process: it is already
# running and owns the radio. Toggling the radio is the right granularity here,
# and doing it through nmcli keeps NM's state machine in agreement with reality.
#
# These used to call connmanctl, carried over from the JELOS-based MossySpruce
# base. dArkMoss is Debian and has no connman at all, so both were silently
# doing nothing - the WiFi toggle in settings looked like it worked and did not.
device_wifi_power_on() {
    nmcli radio wifi on >/dev/null 2>&1
}

device_wifi_power_off() {
    nmcli radio wifi off >/dev/null 2>&1
}

# NetworkManager runs its own DHCP. Starting udhcpc alongside it would give the
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

# asound-setup.sh runs immediately before RetroArch and, when there is no
# Bluetooth sink, deletes the .asoundrc in RA's HOME and calls this to write the
# wired one back. Every other platform leaves it to device.sh's stub, because
# their ALSA default lives in /etc/asound.conf and survives a HOME change.
#
# dArkMoss is not like that. Its config is dArkOS's per-user ~/.asoundrc, and
# /etc/asound.conf is empty - so RetroArch, which runs with HOME set to
# /mnt/SDCARD/RetroArch/, loses it and falls through to raw hw:0,0. That costs
# two things: dmix, so anything else holding the PCM makes RA's open fail, and
# the softvol "Master" control, which is the one set_volume above drives. Not
# writing this leaves the in-game volume buttons moving a control that no longer
# affects the sound.
#
# So this is the base's own ~/.asoundrc verbatim rather than a fresh design -
# it is what the hardware is known to work with, and matching it keeps one
# "Master" control in front of both the menu and the emulator.
device_write_default_asound_rc() {
    cat > "$ASOUND_CONF" <<EOF
pcm.!default {
    type        plug
    slave.pcm   "softvol"
}

ctl.!default {
    type        hw
    card        0
}

pcm.ddmix {
    ipc_key     1024
    type        dmix
    slave {
        pcm         "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
        rate        44100
    }
}

pcm.softvol {
    type        softvol
    slave {
        pcm     "ddmix"
    }
    control {
        name    "Master"
        card    0
    }
}
EOF
}

  #############################
#####   MENU LOOP HOOKS   #####
  #############################

# principal.sh calls these around each PyUI session. runtime.sh execs
# principal.sh here like everywhere else, so they run on this device too and
# were logging a miss on every loop.

prepare_for_pyui_launch() {
    # SDL2 startup is the slowest part of reaching the menu, so give it the full
    # clock and drop back once it is up.
    #
    # Deliberately not the Flip's version, which also writes "performance" to
    # /sys/class/devfreq/dmc and never puts it back, leaving the memory
    # controller pinned at its top clock for the rest of the session. The CPU is
    # what PyUI is waiting on here.
    set_performance
    (
        sleep 5
        if flag_check "in_menu"; then
            set_smart
        fi
        unlock_governor 2>/dev/null
    ) &
}

post_pyui_exit() {
    log_message "post_pyui_exit not needed on this device" -v
}

# A live RGB30 reports it has an LED, but the sysfs path has not been found yet,
# so there is nothing to drive. See LED_PATH in RGB30.cfg.
enable_or_disable_rgb() {
    log_message "No controllable RGB LED on this device" -v
}

  ###############################
#####   EMULATION AND PORTS   #####
  ###############################

# ra_functions.sh calls this right before it execs RetroArch. The job is to
# point CORE_DIR at the right core set and echo back the binary to run.
#
# 64-bit only, so there is no 32-bit branch like the Flip's: RGB30.cfg sets
# DEVICE_HAS_32_BIT_RA=false and RA_BIN=ra64.universal, and the cores are the
# aarch64 set in cores64. retroarch-RGB30.cfg already points libretro_directory
# at the same place.
#
# The three per-core library cases are the Flip's, and they apply unchanged
# because this is the same RK3566 and the same aarch64 userland - the files
# those paths name were confirmed to be aarch64 on the card. EASYRPG genuinely
# has no lib-RGB30; lib-Flip is the correct directory here, not a fallback.
setup_for_retroarch() {
    case "$CORE" in
        uae4arm)      export LD_LIBRARY_PATH="$EMU_DIR:$LD_LIBRARY_PATH" ;;
        easyrpg)      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip" ;;
        yabasanshiro) export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib64" ;;
    esac

    export CORE_DIR="$RA_DIR/.retroarch/cores64"

    # A core shipped next to the system's own files wins over the shared set.
    if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
        export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
    else
        export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
    fi

    echo "$RA_BIN"
}

# PortMaster ports location.
#
# harbourmaster installs a port's files flat into Roms/PORTS, but every port
# script computes GAMEDIR=/$directory/ports/<name>, and spruce's control.txt
# sets directory=/mnt/SDCARD/Roms/PORTS - so they look one level deeper, in
# Roms/PORTS/ports. Every other PortMaster device reconciles that by binding
# Roms/PORTS onto Roms/PORTS/ports (Flip.sh, SmartProS.sh, AnbernicXXCommon.sh,
# trimui_a133p.sh); this device had no such hook, so every port died on
# "cd: .../ports/<name>: No such file or directory".
#
# Done here rather than in a boot-time mount block because this is the hook
# run_port already calls, and it keeps the mount to the one moment it is
# needed. Guarded so repeated launches do not stack binds - mountpoint(1) is
# not in this base, so test the mount table.
device_prepare_for_ports_run() {
    mkdir -p /mnt/SDCARD/Roms/PORTS/ports
    if ! grep -q " /mnt/SDCARD/Roms/PORTS/ports " /proc/mounts; then
        mount --bind /mnt/SDCARD/Roms/PORTS /mnt/SDCARD/Roms/PORTS/ports \
            && log_message "RGB30: bound Roms/PORTS onto Roms/PORTS/ports for ports run" -v \
            || log_message "RGB30: failed to bind Roms/PORTS/ports - ports will not find their files"
    fi
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run unneeded on this device" -v
}

# led_functions.sh calls rgb_led unconditionally when a game starts. RGB30.cfg
# reports LED_PATH="not applicable" - a live device says it HAS an LED, but the
# sysfs path for it has not been found yet, so there is nothing to drive. Absorb
# the call rather than let it hit device.sh's "Missing" stub on every launch.
rgb_led() {
    return 0
}

# GameNursery reads this. PyUI keeps its system config beside the app rather
# than in Saves/, and RGB30.cfg's SYSTEM_JSON already points at it - use that
# instead of a second literal that could drift out of step with it.
# The RGB30 ships with no rumble motor, but it is a documented solder mod
# (ArkOS wiki, "How do I add and enable a rumble/vibration motor to my unit"):
# a 1.5-3.0V button motor onto pads Powkiddy left in place, and no software
# change needed - the singleadc-joypad driver already claims the PWM
# (supplier:platform:fe6e0010.pwm) and the pad already advertises FF_RUMBLE.
#
# So this is implemented rather than left as the device.sh stub. On a modded
# unit it buzzes; on a stock one the kernel accepts the effect and nothing
# happens, which is measured behaviour (rc=0, nothing felt) and is exactly what
# the stub did anyway. Costs a stock unit nothing.
#
# Magnitudes are the Anbernic starting values and are UNTUNED here - nobody has
# felt this device. The RG SP turned out to have a floor above 0x2000, so all
# three sit well above it; retuning is shell-side and needs no rebuild.
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

# /dev/fb0 is dead on this device: under DRM it is only an emulated shim and
# reads back all zeros, so every fbdev grab produced a black image. That is why
# this used to fall through to the "Missing take_screenshot function" stub in
# device.sh, and why Saves/states/.gameswitcher was always empty.
#
# The real scanout is a KMS plane, so grab that instead. This captures whatever
# is actually on screen - PyUI, RetroArch, DSperate, anything - because it reads
# the plane rather than any application's buffers, so it needs no cooperation
# from the app. drmModeGetFB2 on another client's framebuffer needs
# CAP_SYS_ADMIN; spruce runs as root here.
#
# Costs about 2.3s on this hardware, nearly all of it ffmpeg startup. That lands
# in the hold-home path ahead of kill_emulator, so the game takes that much
# longer to exit. A dedicated DRM helper would be far quicker if it ever matters.
take_screenshot() {
    screenshot_path="$1"
    [ -n "$screenshot_path" ] || return 1
    # An absolute path, NOT plain "ffmpeg". helperFunctions.sh puts
    # /mnt/SDCARD/spruce/bin64 first on PATH, and that build has no kmsgrab
    # demuxer - it fails with "Unknown input format: 'kmsgrab'". So the capture
    # works when run by hand and fails through spruce's own environment, which
    # is the only way it is ever actually called. Debian's ffmpeg has it, and
    # spruce/bin/ffmpeg does too as a fallback.
    _ff=""
    for _c in /usr/bin/ffmpeg /mnt/SDCARD/spruce/bin/ffmpeg; do
        [ -x "$_c" ] && { _ff="$_c"; break; }
    done
    [ -n "$_ff" ] || {
        log_message "take_screenshot: no ffmpeg with kmsgrab available"
        return 1
    }
    mkdir -p "$(dirname "$screenshot_path")" 2>/dev/null

    if timeout 15 "$_ff" -hide_banner -loglevel error \
        -f kmsgrab -i - \
        -vf "hwdownload,format=bgr0" \
        -frames:v 1 -update 1 -y "$screenshot_path" >/dev/null 2>&1; then
        return 0
    fi

    # Leave nothing behind: a half-written or empty file would show up in the
    # game switcher as a broken thumbnail, which is worse than no thumbnail.
    rm -f "$screenshot_path" 2>/dev/null
    log_message "take_screenshot: kmsgrab capture failed"
    return 1
}

get_config_path() {
    echo "${SYSTEM_JSON:-/mnt/SDCARD/App/PyUI/config/rgb30-system.json}"
}

# The Reset RetroArch Hotkeys task calls this. Values are the ones already
# shipped in retroarch-RGB30.cfg, which were taken from a live RGB30, so a reset
# restores the shipped mapping rather than the Flip's. Hotkey is SELECT (8), and
# the entries deliberately left as "nul" there are reset to "nul" too - a reset
# that only rewrote the bound keys would leave stale bindings behind.
set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"8\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"10\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}

  #########################
#####   IN-GAME MENU   #####
  #########################

# The menu button (a stick click - which one is Button Settings > Menu
# button, resolved into B_MENU by RGB30.cfg) opening the emulator menu in-game
# goes through
# common64bit's send_menu_button_to_retroarch, which pipes MENU_TOGGLE to
# RetroArch's UDP command port with spruce's bundled netcat. That netcat's
# hardcoded ELF loader path does not exist on this base, so it dies with "No
# such file or directory" and the menu never opens. The base ships Debian's own
# netcat-openbsd at /usr/bin/nc (an alternatives symlink to nc.openbsd), which
# needs no loader - use it. Its -u -w1 sends the datagram and exits after a
# second, which is what this needs.
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
    # Ignore SIGHUP for the rest of the shutdown, this hook being the last
    # thing that runs before save_poweroff.sh starts killing processes.
    #
    # stop_problematic_scripts() kills runtime.sh, which here is
    # spruce-launch.service's MainPID, so the unit stops. That unit holds
    # /dev/tty1 with TTYVHangup=yes, and stopping it hangs the terminal up -
    # SIGHUPing everything still on it, the shutdown script included. It died
    # at the very first killall, ~120 commands before the poweroff, and did it
    # silently: the device stayed on, the unit deactivated cleanly, and the log
    # just stopped. Only an execution trace showed where.
    #
    # A trap set in a function applies to the whole shell, and SIG_IGN survives
    # exec, so this covers stage 2 as well.
    #
    # Deliberately here rather than in save_poweroff.sh: it is right for every
    # platform, but shutdown is a bad place to take a fleet-wide risk on one
    # device's evidence. Move it up once another systemd host needs it.
    trap "" HUP

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
