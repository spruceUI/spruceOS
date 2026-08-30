#!/bin/sh

# Shared button-action dispatch.
#
# Both the Menu button (homebutton_watchdog.sh) and, on devices that have one,
# the top Home button (buttons_watchdog.sh -> device_home_button_pressed) run a
# user-chosen action. Those two watchdogs are separate processes, so the action
# logic lives here and both source this file, rather than each carrying its own
# copy. perform_action() takes an action name and does it; the watchdogs only
# resolve which name to run from their own config option.
#
# Requires helperFunctions.sh (get_config_value, take_screenshot, vibrate,
# log_message, rgb_led, led_color_hex, the $B_* / $EVENT_PATH_* vars) to be
# sourced first.

# Pattern for checking emulator usage
EMU_PATTERN="/(mnt/SDCARD|media/sdcard[0,1])/Emu"

kill_port(){
    CMD=$(cat /tmp/cmd_to_run.sh)
    if [[ "$CMD" == *"/Roms/PORTS/"* ]]; then
        rm -f /tmp/menubtn

        capture_screen

        SID=$(cat /tmp/last_port_sid)
        kill -TERM -"$SID" 2>/dev/null
        sleep 2
        kill -9 -"$SID" 2>/dev/null

    fi
}

# TODO bypass all of this if drastic original as killall -15 does not work on it
pause_drastic(){
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        log_message "button_actions.sh: Pausing DraStic."
        killall -q -STOP drastic drastic64
    fi
}

resume_drastic(){
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        log_message "button_actions.sh: Resuming DraStic."
        killall -q -CONT drastic drastic64
    fi
}

kill_drastic() {

    resume_drastic
	log_message "button_actions.sh: Killing DraStic!"
    # use sendevent to send MENU + L1 combo buttons to drastic. Brick needs it twice
    {
        echo $B_L3 1    # Fn1 press
        echo $B_L3 0    # Fn1 release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        echo 0 0 0      # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_DRASTIC &

    killall -q -15 drastic drastic64
}

kill_ppsspp() {
	log_message "button_actions.sh: Killing PPSSPP!"

    # Send SIGUSR1 to trigger save-and-quit (saves state then exits cleanly)
    killall -q -USR1 PPSSPPSDL_TrimUI PPSSPPSDL_SmartProS PPSSPPSDL_Flip PPSSPPSDL_A30 PPSSPPSDL_Pixel2 PPSSPPSDL_h700
}

kill_scummvm() {
	log_message "button_actions.sh: Saving and killing ScummVM!"
    # Send SIGUSR1 to trigger autosave, then wait for it to finish
    killall -q -USR1 scummvm scummvm.64 scummvm.a30 scummvm.mini
    sleep 2
    # SIGTERM as fallback in case it didn't exit
    killall -q -15 scummvm scummvm.64 scummvm.a30 scummvm.mini
}

kill_mupen() {
	log_message "button_actions.sh: Saving and killing mupen64plus!"
    # Send SIGUSR1 to trigger save-state-and-quit
    killall -q -USR1 mupen64plus
    sleep 2
    # SIGTERM as fallback in case it didn't exit
    killall -q -15 mupen64plus
}

kill_gvu() {
	log_message "button_actions.sh: Killing GVU!"
	killall -q -15 gvu
}

kill_pcsx() {
	log_message "button_actions.sh: Saving and killing PCSX-ReARMed!"
    # Send SIGUSR1 to trigger save-state-and-quit
    killall -q -USR1 pcsx_64 pcsx_a30 pcsx_mini
    sleep 2
    # SIGTERM as fallback in case it didn't exit
    killall -q -15 pcsx_64 pcsx_a30 pcsx_mini
}

kill_ra_and_standard_emulators() {
	log_message "button_actions.sh: Killing miscelaneous emus!"
    killall -q -15 ra32.a30 ra32.mini ra32.universal ra64.universal ra64.pixel2 ra64.h700 ra32.h700 retroarch pico8_dyn pico8_64 flycast flycast2024 yabasanshiro yabasanshiro.trimui
}

kill_dsperate() {
	log_message "button_actions.sh: Killing DSperate!"
	# SIGTERM first and give it a moment: DSperate writes the battery save on
	# a launcher's SIGTERM, so -9 straight away loses the last save.
	killall -q -15 dsperate-sdl
	sleep 1
	killall -q -9 dsperate-sdl
}

kill_bigpemu() {
	log_message "button_actions.sh: Killing BigPEmu!"
    killall -q -9 gptokeyb2
    killall -q -15 bigpemu
    sleep 1
    killall -q -9 bigpemu
}

kill_vtree() {
    kill -15 $(pgrep -f vtree)
}

kill_emulator() {
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        kill_drastic
    elif pgrep -f "./PPSSPPSDL" >/dev/null; then
        kill_ppsspp
    elif pgrep -f "./scummvm" >/dev/null; then
        kill_scummvm
    elif pgrep -f "mupen64plus" >/dev/null; then
        kill_mupen
    elif pgrep -f "pcsx_64|pcsx_a30|pcsx_mini" >/dev/null; then
        kill_pcsx
    elif pgrep "gvu" >/dev/null; then
        kill_gvu
    elif pgrep dsperate-sdl >/dev/null; then
        # Plain pgrep, not -f: busybox pgrep -f can match its own command line,
        # and "dsperate-sdl" would appear in it.
        kill_dsperate
    elif pgrep -f "bigpemu" >/dev/null; then
        kill_bigpemu
    elif pgrep -f "vtree" >/dev/null; then
        kill_vtree
    else
        kill_ra_and_standard_emulators
    fi
}

update_gameswitcher_json() {
    CMD="$1"
    SCREENSHOT_NAME="$2"

    # -------------------------------
    # Extract system + rom path
    # -------------------------------
    game_system_name="$(printf '%s' "$CMD" | sed -n 's:.*Emu/\([^/]*\)/.*:\1:p')"
    rom_file_path="$(printf '%s' "$CMD" | sed 's:.*"\([^"]*\)" *$:\1:')"
    rom_file_path=$(readlink -f "$rom_file_path")
    # Keep consistent between devices
    # TODO move to device so we don't make this a giant list of regexs
    rom_file_path="${rom_file_path//\/sdcard\//\/SDCARD\/}"
    case "$rom_file_path" in
        /mnt/SDCARD/mmc*/?*)
            rom_file_path="/mnt/SDCARD/${rom_file_path#*/mnt/SDCARD/mmc*/}"
            ;;
    esac
    gameswitcher_json="/mnt/SDCARD/Saves/gameswitcher.json"

    # Create file if missing
    [ ! -f "$gameswitcher_json" ] && echo "[]" > "$gameswitcher_json"
    if ! head -c 1 "$gameswitcher_json" | grep -q '[\[{]'; then
        ts="$(date +%Y%m%d-%H%M%S)"
        bak="${gameswitcher_json}.bak.$ts"

        log_message "button_actions.sh: JSON invalid/empty, backing up to $bak"

        # Only move if file exists
        [ -f "$gameswitcher_json" ] && mv "$gameswitcher_json" "$bak"

        echo "[]" > "$gameswitcher_json"
    fi

    tmpfile="$(mktemp)"

    # -------------------------------
    # Update JSON (remove duplicates + add new entry to top)
    # -------------------------------
    jq --arg rom_file_path "$rom_file_path" \
       --arg game_system_name "$game_system_name" '
        map(select(.rom_file_path != $rom_file_path)) |
        ([{
            rom_file_path: $rom_file_path,
            game_system_name: $game_system_name
        }] + .)
       ' "$gameswitcher_json" > "$tmpfile"

    log_message "Added $rom_file_path to $gameswitcher_json"
    mv "$tmpfile" "$gameswitcher_json"
}



capture_screen(){
    # capture screenshot
    CMD=$(cat /tmp/cmd_to_run.sh)
    GAME_PATH=$(echo "$CMD" | grep -o '".*"' | tail -n1 | tr -d '"')
    GAME_NAME="${GAME_PATH##*/}"
    SHORT_NAME="${GAME_NAME%.*}"
    mkdir -p "/mnt/SDCARD/Saves/states/.gameswitcher"
    SCREENSHOT_NAME="/mnt/SDCARD/Saves/states/.gameswitcher/${SHORT_NAME}.state.auto.png"

    take_screenshot "$SCREENSHOT_NAME"

    log_message "button_actions.sh: 'SCREENSHOT_NAME': $SCREENSHOT_NAME"
}

prepare_game_switcher() {
    # if in game or app now
    if [ -f /tmp/cmd_to_run.sh ]; then

        # get game path
        CMD=$(cat /tmp/cmd_to_run.sh)


        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v -E "$EMU_PATTERN"; then
            log_message "button_actions.sh: Not in game, bypassing game switcher."
            return 0
        fi

        SCREENSHOT_NAME=$(capture_screen)

        update_gameswitcher_json "$CMD" "$SCREENSHOT_NAME"
        touch /mnt/SDCARD/App/PyUI/pyui_gs_trigger

        kill_emulator
        kill_port

    # if in MainUI menu
    elif pgrep "MainUI" >/dev/null; then

        log_message "button_actions.sh: letting PyUI handle menu button"
        # otherwise other program is running, exit normally
    else
        log_message "button_actions.sh: /tmp/cmd_to_run.sh not found and MainUI is not running, bypassing game switcher."
        return 0
    fi

}

perform_action() {
    # handle short press
    case $1 in
    "Game Switcher")
        prepare_game_switcher
        ;;
    "Emulator menu")
        if pgrep -f "./PPSSPPSDL" >/dev/null; then
            killall -q -USR2 PPSSPPSDL_TrimUI PPSSPPSDL_SmartProS PPSSPPSDL_Flip PPSSPPSDL_A30 PPSSPPSDL_Pixel2 PPSSPPSDL_h700
        elif pgrep -f "pcsx_64|pcsx_a30|pcsx_mini" >/dev/null; then
            killall -q -USR2 pcsx_64 pcsx_a30 pcsx_mini
        elif pgrep -f "mupen64plus" >/dev/null; then
            killall -q -USR2 mupen64plus
        else
            send_menu_button_to_retroarch
        fi
        ;;
    "Exit game")
        # resume MainUI if it is running
        # and it will then read menu up event and show popup menu
        killall -q -CONT MainUI
        # or kill any emulator
        kill_emulator
        ;;
    "Toggle LED")
        toggle_led
        ;;
    "Screenshot")
        ts="$(date '+_%Y.%m.%d_%H.%M.%S.png')"
        mkdir -p /mnt/SDCARD/Saves/screenshots
        take_screenshot "/mnt/SDCARD/Saves/screenshots/$PLATFORM$ts"
        vibrate &
        ;;
    "Nothing")
        log_message "button_actions.sh: action 'Nothing', nothing to do"
        ;;
        *)
            log_message "button_actions.sh: $1 is an unknown action to perform"
            ;;
    esac
    killall sendevent
}
