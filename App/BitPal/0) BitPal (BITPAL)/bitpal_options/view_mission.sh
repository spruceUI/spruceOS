#!/bin/sh
MENU="${MENU:-bitpal_menu.txt}"
BITPAL_DIR="${BITPAL_DIR:-./bitpal_data}"
BITPAL_DATA="${BITPAL_DATA:-$BITPAL_DIR/bitpal_data.txt}"
ACTIVE_MISSIONS_DIR="${ACTIVE_MISSIONS_DIR:-$BITPAL_DIR/active_missions}"
COMPLETED_FILE="${COMPLETED_FILE:-$BITPAL_DIR/completed.txt}"
FACE_DIR="../bitpal_faces"

[ -f "$BITPAL_DATA" ] && . "$BITPAL_DATA"
[ -z "$name" ] && name="BitPal"
[ -z "$level" ] && level=1
[ -z "$xp" ] && xp=0
[ -z "$xp_next" ] && xp_next=100
[ -z "$mood" ] && mood="happy"
[ -z "$last_visit" ] && last_visit=$(date +%s)
[ -z "$missions_completed" ] && missions_completed=0

get_face() {
    case "$mood" in
        excited) echo "(^o^)" ;;
        happy)   echo "(^-^)" ;;
        neutral) echo "(-_-)" ;;
        sad)     echo "(;_;)" ;;
        angry)   echo "(>_<)" ;;
        surprised) echo "(O_O)" ;;
        *)       echo "(^-^)" ;;
    esac
}

format_time() {
    local seconds="$1"
    [ -z "$seconds" ] && seconds=0
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

prepare_resume() {
    CURRENT_PATH=$(dirname "$1")
    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
    ROM_PLATFORM=""
    while [ -z "$ROM_PLATFORM" ]; do
        [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
        ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
        [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
    done
    BASE_PATH="/mnt/SDCARD/.userdata/shared/.minui/$ROM_PLATFORM"
    ROM_NAME=$(basename "$1")
    SLOT_FILE="$BASE_PATH/$ROM_NAME.txt"
    [ -f "$SLOT_FILE" ] && cat "$SLOT_FILE" > /tmp/resume_slot.txt
}

update_background() {
    local mood_to_use="$1"
    local bg_dir="$FACE_DIR"
    files=$(ls "$bg_dir"/background_"${mood_to_use}"_*.png 2>/dev/null)
    if [ -n "$files" ]; then
         set -- $files
         count=$#
         random_index=$((RANDOM % count + 1))
         eval chosen=\$$random_index
         cp "$chosen" "../background.png"
    else
         local bg_src="$bg_dir/background_${mood_to_use}.png"
         [ -f "$bg_src" ] && cp "$bg_src" "../background.png"
    fi
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

face=$(get_face)

if [ -z "$ACTIVE_MISSION" ]; then
    mission_found=0
    for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
        [ -f "$mission_file" ] && { mission_found=1; ACTIVE_MISSION="$mission_file"; break; }
    done
    [ "$mission_found" -eq 0 ] && { ./show_message "$face|No active mission.|Start a new mission first." -l a; exit 0; }
fi

mission=$(cat "$ACTIVE_MISSION")
desc=$(echo "$mission" | cut -d'|' -f1)
target=$(echo "$mission" | cut -d'|' -f2)
type=$(echo "$mission" | cut -d'|' -f3)
mins=$(echo "$mission" | cut -d'|' -f4)
xp_reward=$(echo "$mission" | cut -d'|' -f5)
start_time=$(echo "$mission" | cut -d'|' -f6)
rom_path=$(echo "$mission" | cut -d'|' -f7)
accumulated_time=$(echo "$mission" | cut -d'|' -f8)
[ -z "$accumulated_time" ] && accumulated_time=0
target_seconds=$((mins * 60))
if [ "$accumulated_time" -ge "$target_seconds" ]; then
    finalize_mission "$ACTIVE_MISSION"
else
    percent=$(( accumulated_time * 100 / target_seconds ))
    [ "$percent" -gt 100 ] && percent=100
    played_time=$(format_time "$accumulated_time")
    required_time=$(format_time "$target_seconds")
    progress_text="$played_time of $required_time ($percent%)"
    ./show_message "$face|Mission Progress|$desc|Progress: $progress_text|Reward: $xp_reward XP" -l a

    echo "Resume Mission|launch|action" > /tmp/mission_view.txt
    echo "Cancel Mission|cancel|action" >> /tmp/mission_view.txt

    choice=$(./picker "/tmp/mission_view.txt" -a "SELECT" -b "BACK")
    status=$?
    if [ $status -eq 0 ]; then
        action=$(echo "$choice" | cut -d'|' -f2)
        case "$action" in
            launch)
                if [ -f "$rom_path" ]; then
                    CURRENT_PATH=$(dirname "$rom_path")
                    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
                    ROM_PLATFORM=""
                    while [ -z "$ROM_PLATFORM" ]; do
                        [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
                        ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
                        [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
                    done
                    prepare_resume "$rom_path"
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
                    mission=$(cat "$ACTIVE_MISSION")
                    field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                    if [ "$field_count" -lt 8 ]; then
                        current_accum=0
                    else
                        current_accum=$(echo "$mission" | cut -d'|' -f8)
                    fi
                    new_total=$((current_accum + SESSION_DURATION))
                    if [ "$field_count" -lt 8 ]; then
                        mission=$(echo "$mission" | sed "s/\$/|${new_total}/")
                    else
                        mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                    fi
                    echo "$mission" > "$ACTIVE_MISSION"
                    if [ "$new_total" -ge "$target_seconds" ]; then
                        finalize_mission "$ACTIVE_MISSION"
                    fi
                else
                    ./show_message "Game file not found|$rom_path" -l a
                fi
                ;;
            cancel)
                stored_rom_path="$rom_path"
                
                ./show_message "$face|Cancel Mission?|$desc|Are you sure you want|to cancel this mission?" -l -a "YES" -b "NO"
                if [ $? -eq 0 ]; then
                    if [ -n "$stored_rom_path" ] && [ -f "$stored_rom_path" ]; then
                        restore_game_switcher "$stored_rom_path"
                    fi
                    if [ $((RANDOM % 100)) -lt 70 ]; then
                        mood="sad"
                    else
                        mood="angry"
                    fi
                    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
                    if [ -f "$FACE_DIR/$mood.png" ]; then
                        show.elf "$FACE_DIR/$mood.png" &
                        sleep 2
                        killall show.elf 2>/dev/null
                    fi
                    update_background "$mood"
                    face=$(get_face)
                    
                    rm -f "$ACTIVE_MISSION"
                    
                    case "$mood" in
                        sad)
                            ./show_message "$face|*sniff*|I was really hoping|we'd finish that one..." -l a
                            ;;
                        angry)
                            ./show_message "$face|MISSION ABORTED!|All that progress... WASTED!|*digital grumbling*" -l a
                            ;;
                        *)
                            ./show_message "$face|Mission canceled.|You can start a new|mission now." -l a
                            ;;
                    esac
                    
                    if [ -n "$stored_rom_path" ] && [ -f "$stored_rom_path" ]; then
                        ./show_message "$face|Didn't like that game?|Want to delete it from|your device?" -l -a "DELETE" -b "KEEP"
                        if [ $? -eq 0 ]; then
                            ./show_message "$face|WARNING: PERMANENT ACTION|This will permanently delete|the game from your SD card.|Are you absolutely sure?" -l -a "YES, DELETE IT" -b "NO, KEEP IT"
                            if [ $? -eq 0 ]; then
                                rm -f "$stored_rom_path"
                                ./show_message "$face|Game deleted!|You'll never see|that game again!" -l a
                            else
                                ./show_message "$face|Game kept safe!|Maybe it'll grow on you|with more playtime." -l a
                            fi
                        fi
                    fi
                fi
                ;;
        esac
    fi
    rm -f /tmp/mission_view.txt
fi
exit 0