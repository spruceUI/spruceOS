#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh

run_sd_card_fix_if_triggered() {
    needs_fix=false
    if [ -e /mnt/SDCARD/FIX_MY_SDCARD ]; then
        needs_fix=true
        log_message "/mnt/SDCARD/FIX_MY_SDCARD detected."
    elif read_only_check; then
        needs_fix=true
    fi

    if [ "$needs_fix" = "true" ]; then
        log_message "Running repairSD.sh..."
        mkdir -p /tmp/sdfix
        cp /mnt/SDCARD/spruce/scripts/tasks/repairSD.sh /tmp/sdfix/
        chmod 777 /tmp/sdfix/repairSD.sh
        /tmp/sdfix/repairSD.sh run
    fi
}

hide_fw_app() {
    jq 'if .label then ."#label" = .label | del(.label) else . end' /mnt/SDCARD/App/-FirmwareUpdate-/config.json > /mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp && mv /mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp /mnt/SDCARD/App/-FirmwareUpdate-/config.json
}

show_fw_app() {
    jq 'if ."#label" then .label = ."#label" | del(."#label") else . end' /mnt/SDCARD/App/-FirmwareUpdate-/config.json > /mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp && mv /mnt/SDCARD/App/-FirmwareUpdate-/config.json.tmp /mnt/SDCARD/App/-FirmwareUpdate-/config.json
}

# Define the function to check and hide the firmware update app
check_and_handle_firmware_app() {
    need_fw_update="$(check_if_fw_needs_update)"
    if [ "$need_fw_update" = "true" ]; then
        show_fw_app
    else
        hide_fw_app
    fi
}

check_for_update() {

    SD_CARD="/mnt/SDCARD"
    OTA_URL="https://spruceui.github.io/OTA/spruce"
    TMP_DIR="$SD_CARD/App/-OTA/tmp"
    CONFIG_FILE="$SD_CARD/App/-OTA/config.json"

    should_check="$(get_config_value '.menuOptions."System Settings".checkForUpdates.selected' "True")"
    if [ "$should_check" = "False" ]; then
        return 1
    fi

    timestamp_file="$SD_CARD/App/-OTA/last_check.timestamp"
    check_interval=86400  # 24 hours in seconds

    # If update was previously prompted, check the timestamp
    if flag_check "update_prompted"; then
        # Create timestamp file if it doesn't exist
        [ ! -f "$timestamp_file" ] && date +%s > "$timestamp_file"
        
        current_time=$(date +%s)
        last_check=$(cat "$timestamp_file")
        time_diff=$((current_time - last_check))
        
        # If less than 24 hours have passed, skip the check
        if [ $time_diff -lt $check_interval ]; then
            log_message "Update Check: Skipping check, last check was $((time_diff / 3600)) hours ago"
            return 1
        fi
    fi

    mkdir -p "$TMP_DIR"

    # Update timestamp for next check
    date +%s > "$timestamp_file"

    # Check for Wi-Fi enabled status first
    wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$SYSTEM_JSON")
    if [ "$wifi_enabled" -eq 0 ]; then
        log_message "Update Check: WiFi is disabled, exiting."
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Try up to 3 times to get a connection
    attempts=0
    while [ $attempts -lt 3 ]; do
        if ping -c 3 spruceui.github.io >/dev/null 2>&1; then
            break
        fi
        attempts=$((attempts + 1))
        if [ $attempts -eq 3 ]; then
            log_message "Update Check: Failed to establish network connection after 3 attempts."
            rm -rf "$TMP_DIR"
            return 1
        fi
        log_message "Update Check: Waiting for network connection (attempt $attempts of 3)..."
        sleep 20
    done

    # Get current version based on mode
    if flag_check "developer_mode" || flag_check "tester_mode" || flag_check "beta"; then
        CURRENT_VERSION=$(get_version_complex)
    else
        CURRENT_VERSION=$(get_version)
    fi

    read_only_check

    log_message "Update Check: Current version: $CURRENT_VERSION"

    # Download and parse the release info file
    if ! curl -s -o "$TMP_DIR/spruce" "$OTA_URL"; then
        log_message "Update Check: Failed to download release info"
        rm -rf "$TMP_DIR"
        return 1
    fi

    # Extract version info from downloaded file
    RELEASE_VERSION=$(sed -n 's/RELEASE_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    NIGHTLY_VERSION=$(sed -n 's/NIGHTLY_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')
    BETA_VERSION=$(sed -n 's/BETA_VERSION=//p' "$TMP_DIR/spruce" | tr -d '\n\r')

    # Set target version based on developer/tester mode
    TARGET_VERSION="$RELEASE_VERSION"
    if flag_check "beta"; then
        TARGET_VERSION="$BETA_VERSION"
    fi

    if flag_check "developer_mode" || flag_check "tester_mode"; then
        TARGET_VERSION="$NIGHTLY_VERSION"
    fi

    # Compare versions, handling nightly date format and beta versions
    log_message "Update Check: Comparing versions: $TARGET_VERSION vs $CURRENT_VERSION"
    
    # Extract base version, date, and beta status
    current_base_version=$(echo "$CURRENT_VERSION" | cut -d'-' -f1)
    current_suffix=$(echo "$CURRENT_VERSION" | cut -d'-' -f2 -s)
    current_is_beta=$(echo "$current_suffix" | grep -q "Beta" && echo "1" || echo "0")
    current_date=$(echo "$current_suffix" | grep -qE "^[0-9]{8}$" && echo "$current_suffix" || echo "")

    target_base_version=$(echo "$TARGET_VERSION" | cut -d'-' -f1)
    target_suffix=$(echo "$TARGET_VERSION" | cut -d'-' -f2 -s)
    target_is_beta=$(echo "$target_suffix" | grep -q "Beta" && echo "1" || echo "0")
    target_date=$(echo "$target_suffix" | grep -qE "^[0-9]{8}$" && echo "$target_suffix" || echo "")

    update_available=0
    
    # Compare base versions first
    version_higher=$(echo "$target_base_version $current_base_version" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print "0"; exit} else if (a[i]>b[i]) {print "1"; exit}} print "0"}')
    
    if [ "$version_higher" = "1" ]; then
        # Target version is higher, always consider it an update
        update_available=1
    elif [ "$version_higher" = "0" ] && [ "$target_base_version" = "$current_base_version" ]; then
        # Same base version, check suffixes
        if flag_check "developer_mode" || flag_check "tester_mode"; then
            # For testers/developers, nightlies are updates
            if [ -n "$target_date" ] && [ -n "$current_date" ] && [ "$target_date" -gt "$current_date" ]; then
                update_available=1
            fi
        elif flag_check "beta"; then
            # Beta mode logic
            if [ "$current_is_beta" = "1" ]; then
                # Currently on beta, only higher base versions are updates
                update_available=0
            elif [ "$target_is_beta" = "1" ]; then
                # Not on beta, but target is beta - consider it an update
                update_available=1
            fi
        fi
    fi

    if [ $update_available -eq 1 ]; then
        log_message "Update Check: Update available"
        # Update is available - show app and set label and description
        jq --arg ver "$TARGET_VERSION" '
          (if ."#label" then del(."#label") else . end)
          | .label = "Update Available"
          | .description = "Version \($ver) is available"
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        rm -rf "$TMP_DIR"

        # Check if update was previously prompted
        if ! flag_check "update_prompted"; then
            # First time seeing this update
            flag_add "update_available"
            flag_add "update_prompted"
            echo "$TARGET_VERSION" > "$(flag_path update_prompted)"
            echo "$TARGET_VERSION" > "$(flag_path update_available)"
        else
            # Get version from previous prompt
            prompted_version=$(cat "$(flag_path update_prompted)")
            
            # Compare versions (using same logic as above)
            prompted_base_version=$(echo "$prompted_version" | cut -d'-' -f1)
            prompted_date=$(echo "$prompted_version" | cut -d'-' -f2 -s)
            
            newer_than_prompted=0
            if [ "$(echo "$target_base_version $prompted_base_version" | awk '{split($1,a,"."); split($2,b,"."); for (i=1; i<=3; i++) {if (a[i]<b[i]) {print $2; exit} else if (a[i]>b[i]) {print $1; exit}} print $2}')" != "$prompted_base_version" ]; then
                newer_than_prompted=1
            elif [ -n "$prompted_date" ] && [ -n "$target_date" ] && [ "$target_date" -gt "$prompted_date" ]; then
                newer_than_prompted=1
            fi

            if [ $newer_than_prompted -eq 1 ]; then
                # New version is newer than previously prompted version
                flag_add "update_available"
                echo "$TARGET_VERSION" > "$(flag_path update_prompted)"
                echo "$TARGET_VERSION" > "$(flag_path update_available)"
            fi
        fi
        return 0
    else
        log_message "Update Check: Current version is up to date"
        # No update - if app is visible, set label and description back to default
        if grep -q '"label"' "$CONFIG_FILE"; then
            jq '.label = "Check for Updates" | .description = "Download and install updates over Wi-Fi"' \
              "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        fi
        rm -rf "$TMP_DIR"
        return 1
    fi
}

update_checker(){
    sleep 20
    check_for_update
}

check_for_update_file() {
    echo "Searching for update file"
    UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
    echo "Found update file: $UPDATE_FILE"

    if [ -z "$UPDATE_FILE" ]; then
        echo "No update file found"
        return 1
    fi
    return 0
}

# Function to check and hide the Update App if necessary
check_and_hide_update_app() {
    if ! check_for_update_file; then
        jq 'if .label then ."#label" = .label | del(.label) else . end' "/mnt/SDCARD/App/-Updater/config.json" > "/mnt/SDCARD/App/-Updater/config.json.tmp" && mv "/mnt/SDCARD/App/-Updater/config.json.tmp" "/mnt/SDCARD/App/-Updater/config.json"
        log_message "No update file found; hiding Updater app"
    else
        jq 'if ."#label" then .label = ."#label" | del(."#label") else . end' "/mnt/SDCARD/App/-Updater/config.json" > "/mnt/SDCARD/App/-Updater/config.json.tmp" && mv "/mnt/SDCARD/App/-Updater/config.json.tmp" "/mnt/SDCARD/App/-Updater/config.json"
        log_message "Update file found; Updater app is visible"
    fi
}

developer_mode_task() {
    if flag_check "developer_mode"; then
        samba_enabled="$(get_config_value '.menuOptions."Network Settings".enableSamba.selected' "False")"
        ssh_enabled="$(get_config_value '.menuOptions."Network Settings".enableSSH.selected' "False")"
        ssh_service=$(get_ssh_service_name)

        if [ "$samba_enabled" = "True" ] || [ "$ssh_enabled" = "True" ]; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.2
            done

            if [ "$samba_enabled" = "True" ] && ! pgrep "smbd" > /dev/null; then
                log_message "Dev Mode: Samba starting..."
                start_samba_process
            fi

            if [ "$ssh_enabled" = "True" ] && ! pgrep "$ssh_service" > /dev/null; then
                log_message "Dev Mode: $ssh_service starting..."
                start_ssh_process
            fi
        fi
    fi
}

rotate_logs_background() {
        # Rotate logs spruce5.log -> spruce4.log -> spruce3.log -> etc.
        i=$((max_log_files - 1))
        while [ $i -ge 1 ]; do
            if [ -f "$log_dir/spruce${i}.log" ]; then
                mv "$log_dir/spruce${i}.log" "$log_dir/spruce$((i+1)).log"
            fi
            i=$((i - 1))
        done

        # Move the temporary file to spruce1.log
        if [ -f "$log_target.tmp" ]; then
            mv "$log_target.tmp" "$log_dir/spruce1.log"
        fi
}

rotate_logs() {
    log_dir="/mnt/SDCARD/Saves/spruce"
    log_target="$log_dir/spruce.log"
    max_log_files=5

    # Create the log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # If spruce.log exists, move it to a temporary file
    if [ -f "$log_target" ]; then
        mv "$log_target" "$log_target.tmp"
    fi

    # Create a fresh spruce.log immediately
    touch "$log_target"

    # Perform log rotation in the background
    rotate_logs_background &
}

unstage_archive() {
    ARC_DIR="/mnt/SDCARD/spruce/archives"
    STAGED_ARCHIVE="$1"
    TARGET="$2"
    if [ -z "$TARGET_FOLDER" ] || [ "$TARGET_FOLDER" != "preCmd" ]; then TARGET="preMenu"; fi

    if [ -f "$ARC_DIR/staging/$STAGED_ARCHIVE" ]; then
        log_message "$STAGED_ARCHIVE detected in spruce/archives/staging. Moving into place!"
        mv -f "$ARC_DIR/staging/$STAGED_ARCHIVE" "$ARC_DIR/$TARGET/$STAGED_ARCHIVE"
    fi
}

unstage_archives_wanted() {
    if [ "$DISPLAY_WIDTH" = "640" ] && [ "$DISPLAY_HEIGHT" = "480" ]; then
        unstage_archive "overlays_640x480.7z" "preCmd"
    elif [ "$DISPLAY_WIDTH" = "1024" ] && [ "$DISPLAY_HEIGHT" = "768" ]; then
        unstage_archive "overlays_1024x768.7z" "preCmd"
    fi
    if [ "$DEVICE_CAN_USE_EXTERNAL_CONTROLLER" = "true" ]; then
        unstage_archive "autoconfig.7z" "preCmd"
    fi
    if [ "$DEVICE_USES_64_BIT_RA" = "true" ]; then
        unstage_archive "cores64.7z" "preCmd"
    else
        unstage_archive "cores32.7z" "preCmd"
    fi
}

UPDATE_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"

# This works with checker to display a notification if an update is available
# But only on next boot. So if they find the app by themselves it's fine.
update_notification(){
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        exit 1
    fi

    if flag_check "update_available"; then
        available_version=$(cat "$(flag_path update_available)")
        display --icon "$UPDATE_ICON" -t "Update available!
Version ${available_version} is ready to install
Go to Apps and look for 'Update Available'" --okay
        flag_remove "update_available"
    fi
}


set_volume_to_config() {
    vol=$(jq -r '.vol // empty' "$SYSTEM_JSON")
    [ -n "$vol" ] && set_volume "$vol"
}

emit_startup_av_trace_from_config() {
    "$SYSTEM_EMIT" av-startup-baselines-if-missing "runtimeHelper.sh" || true
}

initialize_system_emit_gate() {
    # Read the persistent ENABLE_TRACE flag once during boot, then mirror the decision into /tmp
    # so hot-path emit checks do not hit the SD card on every invocation.
    mkdir -p "$SYSTEM_EMIT_GATE_DIR" 2>/dev/null || return 1
    rm -f "$SYSTEM_EMIT_GATE_FILE"

    if flag_check "ENABLE_TRACE"; then
        touch "$SYSTEM_EMIT_GATE_FILE"
        rm -f "$SYSTEM_EMIT_GATE_DIR/trace.off"
        return 0
    fi

    touch "$SYSTEM_EMIT_GATE_DIR/trace.off"
    return 1
}

system_emit_gate_enabled() {
    [ -f "$SYSTEM_EMIT_GATE_FILE" ]
}

UNPACK_STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"
FIRSTBOOT_PROGRESS_STATE_FILE="/tmp/firstboot_extract_progress_state"

read_unpack_state() {
    if [ -f "$UNPACK_STATE_FILE" ]; then
        sed -n 's/^state=//p' "$UNPACK_STATE_FILE" | head -n 1
    else
        echo "idle"
    fi
}

read_firstboot_progress_value() {
    key="$1"

    if [ -f "$FIRSTBOOT_PROGRESS_STATE_FILE" ]; then
        sed -n "s/^${key}=//p" "$FIRSTBOOT_PROGRESS_STATE_FILE" | head -n 1
    fi
}

run_unpacker_foreground() {
    launch_event="$1"
    launch_context="$2"
    result_event="$3"
    log_prefix="$4"
    allow_background_state="$5"
    force_foreground_precmd="$6"
    firstboot_ui="$7"

    "$SYSTEM_EMIT" process runtime "$launch_event" "runtimeHelper.sh" "$launch_context" || true
    firstboot_archive_total=""
    firstboot_archive_completed=""
    if [ "${firstboot_ui:-0}" = "1" ]; then
        firstboot_archive_total="$(read_firstboot_progress_value total)"
        firstboot_archive_completed="$(read_firstboot_progress_value completed)"
    fi

    if [ "$force_foreground_precmd" = "1" ]; then
        SPRUCE_FIRSTBOOT_UI="${firstboot_ui:-0}" \
        SPRUCE_FIRSTBOOT_ARCHIVE_TOTAL="${firstboot_archive_total:-0}" \
        SPRUCE_FIRSTBOOT_ARCHIVE_COMPLETED="${firstboot_archive_completed:-0}" \
        UNPACKER_FORCE_FOREGROUND_PRECMD=1 /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    else
        SPRUCE_FIRSTBOOT_UI="${firstboot_ui:-0}" \
        SPRUCE_FIRSTBOOT_ARCHIVE_TOTAL="${firstboot_archive_total:-0}" \
        SPRUCE_FIRSTBOOT_ARCHIVE_COMPLETED="${firstboot_archive_completed:-0}" \
        /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    fi
    [ "${firstboot_ui:-0}" = "1" ] && rm -f "$FIRSTBOOT_PROGRESS_STATE_FILE"

    unpack_state="$(read_unpack_state)"
    if [ "$allow_background_state" = "1" ] && [ "$unpack_state" = "running" ]; then
        log_message "Unpacker: $log_prefix returned with background worker still active."
    else
        log_message "Unpacker: $log_prefix returned with state=$unpack_state."
    fi
    "$SYSTEM_EMIT" process runtime "$result_event" "runtimeHelper.sh" "state=$unpack_state" || true

    if [ "$allow_background_state" = "1" ] && [ "$unpack_state" = "running" ]; then
        return 0
    fi

    [ "$unpack_state" = "complete" ]
}

auto_resume_game() {
    AUTORESUME_ID="$(date +%s)-$$"
    save_active_state="0"; flag_check "save_active" && save_active_state="1"
    in_menu_state="0"; flag_check "in_menu" && in_menu_state="1"
    log_message "Auto Resume[$AUTORESUME_ID] start: save_active=$save_active_state in_menu=$in_menu_state"

    # Ensure device is properly initialized (volume, wifi, etc) before launching auto-resume
    AUTORESUME_INIT_TIMEOUT_SEC=20
    log_message "Auto Resume[$AUTORESUME_ID] init start: launching PyUI startupInitOnly timeout=${AUTORESUME_INIT_TIMEOUT_SEC}s"
    /mnt/SDCARD/App/PyUI/launch.sh -startupInitOnly True &
    init_pid="$!"
    init_timed_out=0
    init_degraded=0
    init_start_ts="$(date +%s)"
    init_next_heartbeat=2
    log_message "Auto Resume[$AUTORESUME_ID] init pid=$init_pid"
    while kill -0 "$init_pid" 2>/dev/null; do
        now_ts="$(date +%s)"
        elapsed=$((now_ts - init_start_ts))
        if [ "$elapsed" -ge "$init_next_heartbeat" ]; then
            log_message "Auto Resume[$AUTORESUME_ID] init wait heartbeat: elapsed=${elapsed}s pid=$init_pid alive=1"
            init_next_heartbeat=$((init_next_heartbeat + 2))
        fi
        if [ "$elapsed" -ge "$AUTORESUME_INIT_TIMEOUT_SEC" ]; then
            init_timed_out=1
            listener_state="absent"
            [ -f /mnt/SDCARD/App/PyUI/realtime_message_network_listener.txt ] && listener_state="present"
            init_cmdline="unavailable"
            if [ -r "/proc/$init_pid/cmdline" ]; then
                init_cmdline="$(tr '\000' ' ' < "/proc/$init_pid/cmdline" 2>/dev/null)"
                [ -z "$init_cmdline" ] && init_cmdline="empty"
            fi
            init_ps="unavailable"
            if command -v ps >/dev/null 2>&1; then
                init_ps="$(ps 2>/dev/null | awk -v p="$init_pid" '$1==p{print; found=1} END{if(!found) print "not-found"}')"
            fi
            log_message "Auto Resume[$AUTORESUME_ID] init timeout: startupInitOnly exceeded ${AUTORESUME_INIT_TIMEOUT_SEC}s (pid=$init_pid); listener=$listener_state cmdline=$init_cmdline ps=$init_ps"
            kill "$init_pid" 2>/dev/null || true
            sleep 1
            kill -9 "$init_pid" 2>/dev/null || true
            if kill -0 "$init_pid" 2>/dev/null; then
                log_message "Auto Resume[$AUTORESUME_ID] init kill result: pid still alive after SIGTERM+SIGKILL"
            else
                log_message "Auto Resume[$AUTORESUME_ID] init kill result: pid exited after timeout"
            fi
            break
        fi
        sleep 0.2
    done
    wait "$init_pid" 2>/dev/null
    init_rc="$?"
    if [ "$init_timed_out" -eq 1 ]; then
        init_degraded=1
        log_message "Auto Resume[$AUTORESUME_ID] init degraded: continuing resume stage without startupInitOnly completion wait_rc=$init_rc"
    else
        log_message "Auto Resume[$AUTORESUME_ID] init complete: startupInitOnly exit_code=$init_rc"
    fi

    # moving rather than copying prevents you from repeatedly reloading into a corrupted NDS save state;
    # copying is necessary for repeated save+shutdown/autoresume chaining though and is preferred when safe.
    MOVE_OR_COPY=cp
    if grep -q "Roms/NDS" "${FLAGS_DIR}/lastgame.lock"; then MOVE_OR_COPY=mv; fi

    # runtimeHelper producer contract:
    # stage once and hand off; principal.sh owns execution and cleanup.
    AUTORESUME_STAGED_FLAG="autoresume_staged"
    AUTORESUME_CONSUMED_FLAG="autoresume_consumed"
    STAGED_PATH="/tmp/cmd_to_run.sh"
    STAGED_TMP="/tmp/cmd_to_run.sh.autoresume.tmp"

    if flag_check "$AUTORESUME_STAGED_FLAG"; then
        log_message "Auto Resume[$AUTORESUME_ID] stage skipped: existing staged marker already present."
        return 1
    fi

    rm -f "$STAGED_TMP" "$STAGED_PATH"
    log_message "Auto Resume[$AUTORESUME_ID] stage attempt: source=/mnt/SDCARD/spruce/flags/lastgame.lock target=$STAGED_PATH mode=$MOVE_OR_COPY degraded_init=$init_degraded"
    if $MOVE_OR_COPY "/mnt/SDCARD/spruce/flags/lastgame.lock" "$STAGED_TMP"; then
        mv -f "$STAGED_TMP" "$STAGED_PATH" || return 1
        chmod a+x "$STAGED_PATH"
        flag_add "$AUTORESUME_STAGED_FLAG" --tmp
        flag_remove "$AUTORESUME_CONSUMED_FLAG"
        sync
        if [ "$init_degraded" -eq 1 ]; then
            log_message "Auto Resume[$AUTORESUME_ID] staged for principal.sh execution (degraded_init=1 stage_once=1 path=$STAGED_PATH)"
        else
            log_message "Auto Resume[$AUTORESUME_ID] staged for principal.sh execution (stage_once=1 path=$STAGED_PATH)"
        fi
    else
        rm -f "$STAGED_TMP" "$STAGED_PATH"
        flag_remove "$AUTORESUME_STAGED_FLAG"
        log_message "Auto Resume[$AUTORESUME_ID] staging failed (lastgame.lock copy/move failed); fallback to normal menu boot path."
        return 1
    fi

    return 0
}

set_up_boot_action() {
    BOOT_ACTION="$(get_config_value '.menuOptions."System Settings".bootTo.selected' "spruceUI")"
    if ! flag_check "save_active"; then
        log_message "Selected boot action is $BOOT_ACTION."
        case "$BOOT_ACTION" in
            "Random Game")
                echo "\"/mnt/SDCARD/App/RandomGame/random.sh\"" > /tmp/cmd_to_run.sh
                ;;
            "Game Switcher")
                touch /mnt/SDCARD/App/PyUI/pyui_gs_trigger
                ;;
            "Splore")
                log_message "Attempting to boot into Pico-8. Checking for binaries"
                if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
                    PICO8_EXE="pico8_dyn"
                else
                    PICO8_EXE="pico8_64"
                fi
                if [ -f "/mnt/SDCARD/BIOS/pico8.dat" ] && [ -f "/mnt/SDCARD/BIOS/$PICO8_EXE" ]; then
                    echo "\"/mnt/SDCARD/Emu/PICO8/../../spruce/scripts/emu/standard_launch.sh\" \"/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore\"" > /tmp/cmd_to_run.sh
                else
                    log_message "Pico-8 binaries not found; booting to spruceUI instead."
                fi
                ;;
            "Apotris"*)
                log_message "Sun mode engaged."
                GAME_PATH=/mnt/SDCARD/Roms/GBA/Apotris.gba
                if [ -f "$GAME_PATH" ]; then
                    echo "\"/mnt/SDCARD/Emu/GBA/../../spruce/scripts/emu/standard_launch.sh\" \"$GAME_PATH\"" > /tmp/cmd_to_run.sh
                else
                    log_message "Sun's literal entire romset not found; booting to spruceUI instead."
                fi
                ;;
        esac
    fi
}
