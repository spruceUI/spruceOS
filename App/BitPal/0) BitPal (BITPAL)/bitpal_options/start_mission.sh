#!/bin/sh
MENU="${MENU:-bitpal_menu.txt}"
BITPAL_DIR="${BITPAL_DIR:-./bitpal_data}"
BITPAL_DATA="${BITPAL_DATA:-$BITPAL_DIR/bitpal_data.txt}"
ACTIVE_MISSIONS_DIR="${ACTIVE_MISSIONS_DIR:-$BITPAL_DIR/active_missions}"
COMPLETED_FILE="${COMPLETED_FILE:-$BITPAL_DIR/completed.txt}"
GTT_LIST="${GTT_LIST:-/mnt/SDCARD/Tools/$PLATFORM/Game Time Tracker.pak/gtt_list.txt}"
ROM_DIR="/mnt/SDCARD/Roms"
SCRIPT_DIR=$(dirname "$0")
mkdir -p "$ACTIVE_MISSIONS_DIR"

get_clean_system_name() {
    local folder_path="$1"
    local folder_name
    folder_name=$(basename "$folder_path")
    clean_name=$(echo "$folder_name" | sed -E 's/^[0-9]+[)\._ -]+//g')
    clean_name=$(echo "$clean_name" | sed 's/ *([^)]*)//g' | sed 's/^ *//;s/ *$//')
    echo "$clean_name"
}

get_clean_rom_name() {
    local rom_path="$1"
    local rom_name
    rom_name=$(basename "$rom_path" | sed 's/\.[^.]*$//')
    clean_name=$(echo "$rom_name" | sed -E 's/^[0-9]+[)\._ -]+//g')
    echo "$clean_name"
}

check_mission_slots() {
    mission_count=$(find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" | wc -l)
    if [ "$mission_count" -ge 5 ]; then
        ./show_message "Maximum missions reached!|You already have 5 active missions.|Complete or cancel one first." -l a
        return 1
    fi
    for slot in 1 2 3 4 5; do
        if [ ! -f "$ACTIVE_MISSIONS_DIR/mission_$slot.txt" ]; then
            echo $slot
            return 0
        fi
    done
}

find_completely_random_game() {
    for i in $(seq 1 5); do
        system_folder=$(get_random_system)
        if [ -n "$system_folder" ]; then
            rom_path=$(get_random_rom "$system_folder")
            if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
                echo "$rom_path"
                return 0
            fi
        fi
    done
    for system_folder in "$ROM_DIR"/*; do
        if [ -d "$system_folder" ] && ! should_ignore_folder "$system_folder" ; then
            rom_path=$(get_random_rom "$system_folder")
            if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
                echo "$rom_path"
                return 0
            fi
        fi
    done
    echo ""
    return 1
}


finalize_mission() {
    mission_file="$1"
    mission=$(cat "$mission_file")
    desc=$(echo "$mission" | cut -d'|' -f1)
    start_time=$(echo "$mission" | cut -d'|' -f6)
    xp_reward=$(echo "$mission" | cut -d'|' -f5)
    complete_time=$(date +%s)
    rom_path=$(echo "$mission" | cut -d'|' -f7)
    if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
        restore_game_switcher "$rom_path"
    fi
    original_level="$level"
    echo "$desc|$start_time|$complete_time|$xp_reward" >> "$COMPLETED_FILE"
    . "$BITPAL_DATA"
    xp=$((xp + xp_reward))
    missions_completed=$((missions_completed + 1))
    while [ "$xp" -ge "$xp_next" ]; do
        xp=$((xp - xp_next))
        level=$((level + 1))
        xp_next=$(( level * 50 + 50 ))
    done
    if [ "$mood" = "sad" ]; then
        mood="neutral"
    elif [ "$mood" = "neutral" ]; then
        mood="happy"
    elif [ "$mood" = "angry" ]; then
        mood="neutral"
    elif [ "$mood" = "surprised" ]; then
        mood="happy"
    elif [ "$mood" = "happy" ] && [ $((RANDOM % 100)) -lt 40 ]; then
        mood="excited"
    fi
    cat > "$BITPAL_DATA" <<EOF
name=$name
level=$level
xp=$xp
xp_next=$xp_next
mood=$mood
last_visit=$(date +%s)
missions_completed=$missions_completed
EOF
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
    rm -f "$mission_file"
    ./show_message "Mission Complete!|$desc complete.|Earned: $xp_reward XP|Current XP: $xp|Level: $level" -l a
    echo "$(date +%s)" > "$BITPAL_DIR/last_mission.txt"
}

mission_slot=$(check_mission_slots)
[ $? -ne 0 ] && exit 0
> /tmp/mission_types.txt
mission_type_count=0
if [ -f "$GTT_LIST" ] && [ "$(grep -c "|launch" "$GTT_LIST")" -gt 2 ]; then
    total_games=$(grep -c "|launch" "$GTT_LIST")
    rand_idx=$((RANDOM % total_games + 1))
    game_line=$(grep "|launch" "$GTT_LIST" | sed -n "${rand_idx}p")
    game_name=$(echo "$game_line" | cut -d'|' -f1 | sed 's/^\[[^]]*\] //')
    game_path=$(echo "$game_line" | cut -d'|' -f2)
    game_plays=$(echo "$game_line" | cut -d'|' -f4)
    if [ -f "$game_path" ]; then
        if [ "$game_plays" -lt 3 ]; then
            mins=$((RANDOM % 10 + 5))
            echo "Rediscover $game_name for $mins minutes|random|$game_path|$mins" >> /tmp/mission_types.txt
        else
            mins=$((RANDOM % 15 + 10))
            echo "Play more $game_name for $mins minutes|random|$game_path|$mins" >> /tmp/mission_types.txt
        fi
        mission_type_count=$((mission_type_count + 1))
    fi
fi
system_folder=$(get_random_system)
if [ -n "$system_folder" ]; then
    system_name=$(get_clean_system_name "$system_folder")
    mins=$((RANDOM % 15 + 5))
    echo "Play a game from $system_name for $mins minutes|system|$system_folder|$mins" >> /tmp/mission_types.txt
    mission_type_count=$((mission_type_count + 1))
fi
system_folder=$(get_random_system)
if [ -n "$system_folder" ]; then
    rom_path=$(get_random_rom "$system_folder")
    if [ -n "$rom_path" ]; then
        system_name=$(get_clean_system_name "$system_folder")
        rom_name=$(basename "$rom_path" | sed 's/\.[^.]*$//')
        clean_rom_name=$(echo "$rom_name" | sed -E 's/^[0-9]+[)\._ -]+//g')
        mins=$((RANDOM % 15 + 5))
        echo "Play $clean_rom_name from $system_name for $mins minutes|random|$rom_path|$mins" >> /tmp/mission_types.txt
        mission_type_count=$((mission_type_count + 1))
    fi
fi
mins=$((RANDOM % 15 + 10))
echo "SURPRISE GAME!|random_surprise|surprise|$mins" >> /tmp/mission_types.txt
if [ "$mission_type_count" -eq 0 ]; then
    mins=$((RANDOM % 15 + 5))
    echo "Play any game for $mins minutes|any|any|$mins" >> /tmp/mission_types.txt
fi
./show_message "Choose Your Mission!|BitPal has some missions for you.|Select one to begin!|Stack up to 5 at a time." -l a
mission_choice=$(./picker "/tmp/mission_types.txt")
mission_status=$?
[ $mission_status -ne 0 ] && { rm -f /tmp/mission_types.txt; exit 0; }
desc=$(echo "$mission_choice" | cut -d'|' -f1)
type=$(echo "$mission_choice" | cut -d'|' -f2)
path=$(echo "$mission_choice" | cut -d'|' -f3)
mins=$(echo "$mission_choice" | cut -d'|' -f4)
case "$type" in
    random) xp_award=$((mins * 7)) ;;
    system) xp_award=$((mins * 6)) ;;
    random_surprise) xp_award=$((mins * 8)) ;;
    any) xp_award=$((mins * 5)) ;;
    *) xp_award=$((mins * 5)) ;;
esac
case "$type" in
    random)
        rom_path="$path"
        game_name=$(get_clean_rom_name "$rom_path")
        echo "$desc|$game_name|$type|$mins|$xp_award|$(date +%s)|$rom_path|0" > "$ACTIVE_MISSIONS_DIR/mission_$mission_slot.txt"
        ;;
    random_surprise)
        random_rom=$(find_completely_random_game)
        if [ -z "$random_rom" ] || [ ! -f "$random_rom" ]; then
            ./show_message "Couldn't find a random game.|Try selecting a specific system instead." -l a
            rm -f /tmp/mission_types.txt
            exit 0
        fi
        echo "SURPRISE GAME!|SURPRISE|$type|$mins|$xp_award|$(date +%s)|$random_rom|0" > "$ACTIVE_MISSIONS_DIR/mission_$mission_slot.txt"
        rom_path="$random_rom"
        ;;
    system)
        system_name=$(get_clean_system_name "$path")
        ./show_message "Choose a Game|Pick any game from|$system_name to complete|your mission" -l a
        selected_rom=$(./directory "$path")
        if [ -z "$selected_rom" ] || [ ! -f "$selected_rom" ]; then
            ./show_message "No game selected.|Mission cancelled." -l a
            rm -f /tmp/mission_types.txt
            exit 0
        fi
        game_name=$(get_clean_rom_name "$selected_rom")
        echo "Play $game_name from $system_name for $mins minutes|$game_name|$type|$mins|$xp_award|$(date +%s)|$selected_rom|0" > "$ACTIVE_MISSIONS_DIR/mission_$mission_slot.txt"
        rom_path="$selected_rom"
        ;;
    any)
        ./show_message "Choose Any Game|Pick any game to complete|your $mins minute mission" -l a
        selected_rom=$(./directory "$ROM_DIR")
        if [ -z "$selected_rom" ] || [ ! -f "$selected_rom" ]; then
            ./show_message "No game selected.|Mission cancelled." -l a
            rm -f /tmp/mission_types.txt
            exit 0
        fi
        game_name=$(get_clean_rom_name "$selected_rom")
        echo "Play $game_name for $mins minutes|$game_name|$type|$mins|$xp_award|$(date +%s)|$selected_rom|0" > "$ACTIVE_MISSIONS_DIR/mission_$mission_slot.txt"
        rom_path="$selected_rom"
        ;;
esac
rm -f /tmp/mission_types.txt
./show_message "Mission $mission_slot Accepted!|$desc|Reward: $xp_award XP|Note: GameSwitcher will be disabled|until this mission is completed." -l -a "START NOW" -b "LATER"
confirm_status=$?
if [ $confirm_status -eq 0 ] && [ -f "$rom_path" ]; then
    CURRENT_PATH=$(dirname "$rom_path")
    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
    ROM_PLATFORM=""
    while [ -z "$ROM_PLATFORM" ]; do
         [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
         ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
         [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
    done
    disable_game_switcher "$rom_path" "$ROM_PLATFORM"
    export SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/current_session.txt"
    export LAST_SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/last_session_duration.txt"
    if echo "$rom_path" | grep -qi "\.sh$"; then
         PORTS_LAUNCH="/mnt/SDCARD/Emus/$PLATFORM/PORTS.pak/launch.sh"
         "$PORTS_LAUNCH" "$rom_path"
    elif [ -d "/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak" ]; then
         EMULATOR="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/launch.sh"
         "$EMULATOR" "$rom_path"
    elif [ -d "/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak" ]; then
         EMULATOR="/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak/launch.sh"
         "$EMULATOR" "$rom_path"
    else
         ./show_message "Emulator not found for $ROM_PLATFORM" -l a
    fi
    SESSION_DURATION=$(cat "$LAST_SESSION_FILE")
    rm -f "$LAST_SESSION_FILE"
    mission_file="$ACTIVE_MISSIONS_DIR/mission_$mission_slot.txt"
    mission=$(cat "$mission_file")
    current_accum=$(echo "$mission" | cut -d'|' -f8)
    new_total=$((current_accum + SESSION_DURATION))
    mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
    echo "$mission" > "$mission_file"
    target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
    if [ "$new_total" -ge "$target_seconds" ]; then
         finalize_mission "$mission_file"
         exit 0
    fi
fi
exit 0