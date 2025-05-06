#!/bin/sh
cd "$(dirname "$0")"
export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH

MENU="bitpal_menu.txt"
DUMMY_ROM="__BITPAL__"
BITPAL_DIR="./bitpal_data"
BITPAL_DATA="$BITPAL_DIR/bitpal_data.txt"
ACTIVE_MISSIONS_DIR="$BITPAL_DIR/active_missions"
COMPLETED_FILE="$BITPAL_DIR/completed.txt"
FACE_DIR="./bitpal_faces"

mkdir -p "$BITPAL_DIR" "$ACTIVE_MISSIONS_DIR" "$FACE_DIR"

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
    
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi

    rm -f "$mission_file"
    ./show_message "Mission Complete!|$desc complete.|Earned: $xp_reward XP|Current XP: $xp|Level: $level" -l a

    echo "$(date +%s)" > "$BITPAL_DIR/last_mission.txt"

    mood="$mood"
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
    
    update_background "$mood"
    
    if [ "$level" -gt "$original_level" ]; then
        ./show_message "Level Up!|BitPal has reached Level $level!|Feel my gaming power grow!" -l a
    elif [ "$mood" != "$1" ]; then
        case "$mood" in
            happy)
                ./show_message "Mood improved!|BitPal is happy now!|Thank you for helping me|complete that mission!" -l a
                ;;
            excited)
                ./show_message "Woohoo!|BitPal is super excited!|That mission was awesome!|Let's keep going!" -l a
                ;;
            neutral)
                ./show_message "I'm feeling better.|That mission helped|improve my mood." -l a
                ;;
        esac
    fi
    
    return 1
}


show_random_fact() {
    fact=$(get_random_fact)
    ./show_message "Gaming Fact!|$fact" -l a
}

show_face() {
    local mood_to_show="$1"
    local duration="${2:-2}"
    if [ -f "$FACE_DIR/$mood_to_show.png" ]; then
        show.elf "$FACE_DIR/$mood_to_show.png" &
        sleep "$duration"
        killall show.elf 2>/dev/null
    fi
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
         cp "$chosen" "./background.png"
    else
         bg_src="$bg_dir/background_${mood_to_use}.png"
         if [ -f "$bg_src" ]; then
             cp "$bg_src" "./background.png"
         fi
    fi
}

load_bitpal_data() {
   . "$BITPAL_DATA"
   [ -z "$name" ] && name="BitPal"
   [ -z "$level" ] && level=1
   [ -z "$xp" ] && xp=0
   [ -z "$xp_next" ] && xp_next=100
   [ -z "$mood" ] && mood="happy"
   [ -z "$last_visit" ] && last_visit=$(date +%s)
   [ -z "$missions_completed" ] && missions_completed=0
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

handle_exit() {
    if [ -f "$BITPAL_DIR/last_mission.txt" ]; then
        LAST_MISSION_TIME=$(cat "$BITPAL_DIR/last_mission.txt")
        CURRENT_TIME=$(date +%s)
        if [ $((CURRENT_TIME - LAST_MISSION_TIME)) -lt 300 ]; then
            cleanup
            exit 0
        fi
    fi
    exit_mood_num=$((RANDOM % 3))
    case $exit_mood_num in
        0) mood="sad" ;;
        1) mood="angry" ;;
        2) mood="surprised" ;;
    esac
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
    if [ $? -eq 0 ]; then
        randompick=$((RANDOM % 2))
        if [ $randompick -eq 0 ]; then
            mood="neutral"
        else
            mood="surprised"
        fi
        sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
        if [ -f "$FACE_DIR/$mood.png" ]; then
            show.elf "$FACE_DIR/$mood.png" &
            sleep 2
            killall show.elf 2>/dev/null
        fi
        update_background "$mood"
        thanks_num=$((RANDOM % 6))
        case $thanks_num in
            0) ./show_message "Phew! ...|I thought I'd be alone!|Thanks for sticking with me!" -l a ;;
            1) ./show_message "You stayed!|BitPal is so relieved!|Let's keep adventuring!" -l a ;;
            2) ./show_message "Yes!|That was close...|I almost lost my player!" -l a ;;
            3) ./show_message "Alright!|Team BitPal is back|and stronger than ever!" -l a ;;
            4) ./show_message "Woohoo!|The quest continues!|Thanks for not leaving me behind." -l a ;;
            5) ./show_message "Hurray!|We're still in the game!|Thank you for staying, hero!" -l a ;;
        esac
        return 0
    else
        cleanup
        exit 0
    fi
}

export SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/current_session.txt"
export LAST_SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/last_session_duration.txt"

load_bitpal_data

missions_completed_at_startup=0

for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
    if [ -f "${mission_file}.complete" ]; then
        original_level="$level"
        original_mood="$mood"
        finalize_mission "$mission_file"
        rm -f "${mission_file}.complete"
        missions_completed_at_startup=1
    fi
done

if [ -f "$BITPAL_DIR/active_mission.txt.complete" ]; then
    original_level="$level"
    original_mood="$mood"
    finalize_mission "$BITPAL_DIR/active_mission.txt"
    rm -f "$BITPAL_DIR/active_mission.txt.complete"
    missions_completed_at_startup=1
fi

for complete_file in "$ACTIVE_MISSIONS_DIR"/*.complete; do
    if [ -f "$complete_file" ]; then
        base_file=$(echo "$complete_file" | sed 's/\.complete$//')
        if [ -f "$base_file" ]; then
            finalize_mission "$base_file"
        fi
        rm -f "$complete_file"
    fi
done

current_time=$(date +%s)
days_since_visit=$(( (current_time - last_visit) / 86400 ))
if [ "$days_since_visit" -ge 3 ]; then
    mood="neutral"
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
fi

if [ "$mood" = "angry" ] || [ "$mood" = "sad" ]; then
    randompick=$((RANDOM % 2))
    if [ $randompick -eq 0 ]; then
        mood="neutral"
    else
        mood="surprised"
    fi
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
fi

sed -i "s/^last_visit=.*/last_visit=$(date +%s)/" "$BITPAL_DATA"

if [ "$missions_completed_at_startup" -eq 0 ]; then
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
fi

update_background "$mood"

face=$(get_face)
CURRENT_DIR=$(basename "$(pwd -P)")
mood_cap=$(echo "$mood" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$mood" | cut -c2-)
BITPAL_TEXT="BitPal - Level $level ($mood_cap)|$DUMMY_ROM|bitpal_options"

[ ! -f "$MENU" ] && echo "$BITPAL_TEXT" > "$MENU"

echo "BitPal Status|bitpal_status" > bitpal_options.txt
echo "Start New Mission|start_mission" >> bitpal_options.txt
[ "$(find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" 2>/dev/null)" ] && echo "Manage Missions|manage_missions" >> bitpal_options.txt
echo "Mission History|mission_history" >> bitpal_options.txt

> mission_options.txt
echo "View Progress|view_mission" > mission_options.txt
echo "Cancel Mission|cancel_mission" >> mission_options.txt

if [ "$missions_completed_at_startup" -eq 0 ]; then
    greeting=$(get_random_greeting)
    ./show_message "$greeting" -l a
    show_random_fact
fi

main_menu_idx=0
while true; do
    load_bitpal_data
    face=$(get_face)
    mood_cap=$(echo "$mood" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$mood" | cut -c2-)
    BITPAL_TEXT="BitPal - Level $level ($mood_cap)|$DUMMY_ROM|bitpal_options"
    update_background "$mood"
    echo "$BITPAL_TEXT" > "$MENU.new"
    for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
        [ -f "$mission_file" ] && {
            mission=$(cat "$mission_file")
            rom_path=$(echo "$mission" | cut -d'|' -f7)
            if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
                mission_desc=$(echo "$mission" | cut -d'|' -f1)
                mission_num=$(basename "$mission_file" | sed 's/mission_\(.*\)\.txt/\1/')
                echo "Mission $mission_num: $mission_desc|$rom_path|launch" >> "$MENU.new"
            fi
        }
    done
    [ -f "$BITPAL_DIR/active_mission.txt" ] && {
        mission=$(cat "$BITPAL_DIR/active_mission.txt")
        rom_path=$(echo "$mission" | cut -d'|' -f7)
        [ -n "$rom_path" ] && [ -f "$rom_path" ] && {
            mission_desc=$(echo "$mission" | cut -d'|' -f1)
            echo "Legacy Mission: $mission_desc|$rom_path|launch" >> "$MENU.new"
        }
    }
    [ -f "$MENU" ] && grep -v "^BitPal " "$MENU" | grep -v "^Mission " | grep -v "^Resume Mission:" | grep -v "^Legacy Mission:" >> "$MENU.new"
    mv "$MENU.new" "$MENU"
    killall picker 2>/dev/null
    picker_output=$(./game_picker "$MENU" -i $main_menu_idx -x "RESUME" -y "OPTIONS" -b "EXIT")
    picker_status=$?
    main_menu_idx=$(grep -n "^${picker_output%$'\n'}$" "$MENU" | cut -d: -f1)
    main_menu_idx=$((main_menu_idx - 1))
    [ $picker_status = 2 ] && handle_exit && continue
    if [ $picker_status = 4 ]; then
        if echo "$picker_output" | grep -q "^BitPal .*|$DUMMY_ROM|bitpal_options"; then
            options_output=$(./picker "bitpal_options.txt")
            options_status=$?
            [ $options_status -ne 0 ] && continue
            option_action=$(echo "$options_output" | cut -d'|' -f2)
            if [ -x "./bitpal_options/${option_action}.sh" ]; then
                export SELECTED_ITEM="$picker_output"
                export MENU
                export BITPAL_DIR
                export BITPAL_DATA
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                export ACTIVE_MISSIONS_DIR
                export COMPLETED_FILE
                "./bitpal_options/${option_action}.sh"
            fi
            continue
        elif echo "$picker_output" | grep -q "^Mission [0-9]"; then
            mission_num=$(echo "$picker_output" | sed -n 's/^Mission \([0-9]\):.*/\1/p')
            mission_file="$ACTIVE_MISSIONS_DIR/mission_${mission_num}.txt"
            [ -f "$mission_file" ] && { export ACTIVE_MISSION="$mission_file"; ./bitpal_options/view_mission.sh; }
            continue
        elif echo "$picker_output" | grep -q "^Legacy Mission:"; then
            [ -f "$BITPAL_DIR/active_mission.txt" ] && { export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"; ./bitpal_options/view_mission.sh; }
            continue
        fi
    fi
    if [ $picker_status = 3 ]; then
        ROM=$(echo "$picker_output" | cut -d'|' -f2)
        if [ -f "$ROM" ]; then
            prepare_resume "$ROM"
            if echo "$ROM" | grep -qi "\.sh$"; then
                PORTS_LAUNCH="/mnt/SDCARD/Emus/$PLATFORM/PORTS.pak/launch.sh"
                if [ -x "$PORTS_LAUNCH" ]; then
                    "$PORTS_LAUNCH" "$ROM" "$@"
                else
                    /bin/sh "$ROM" "$@"
                fi
            else
                CURRENT_PATH=$(dirname "$ROM")
                ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
                ROM_PLATFORM=""
                while [ -z "$ROM_PLATFORM" ]; do
                    [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
                    ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
                    [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
                done
                if [ -d "/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak" ]; then
                    EMULATOR="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/launch.sh"
                    "$EMULATOR" "$ROM"
                elif [ -d "/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak" ]; then
                    EMULATOR="/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak/launch.sh"
                    "$EMULATOR" "$ROM"
                else
                    ./show_message "Emulator not found for $ROM_PLATFORM" -l a
                fi
            fi
            SESSION_DURATION=$(cat "$LAST_SESSION_FILE")
            rm -f "$LAST_SESSION_FILE"
            mission_found=0
            for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
                [ -f "$mission_file" ] && {
                    mission=$(cat "$mission_file")
                    if [ "$ROM" = "$(echo "$mission" | cut -d'|' -f7)" ]; then
                        mission_found=1
                        field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                        if [ "$field_count" -lt 8 ]; then
                            current_accum=0
                        else
                            current_accum=$(echo "$mission" | cut -d'|' -f8)
                        fi
                        new_total=$((current_accum + SESSION_DURATION))
                        mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                        echo "$mission" > "$mission_file"
                        target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                        if [ "$new_total" -ge "$target_seconds" ]; then
                            finalize_mission "$mission_file"
                        fi
                        break
                    fi
                }
            done
        else
            if find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" | grep -q .; then
                ./bitpal_options/manage_missions.sh
            elif [ -f "$BITPAL_DIR/active_mission.txt" ]; then
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                ./bitpal_options/view_mission.sh
            else
                ./bitpal_options/bitpal_status.sh
            fi
        fi
        continue
    fi
    if [ $picker_status = 1 ] || [ $picker_status -gt 4 ]; then
        cleanup
        exit $picker_status
    fi
    action=$(echo "$picker_output" | cut -d'|' -f3)
    case "$action" in
        "launch")
            ROM=$(echo "$picker_output" | cut -d'|' -f2)
            if [ -f "$ROM" ]; then
                prepare_resume "$ROM"
                if echo "$ROM" | grep -qi "\.sh$"; then
                    PORTS_LAUNCH="/mnt/SDCARD/Emus/$PLATFORM/PORTS.pak/launch.sh"
                    if [ -x "$PORTS_LAUNCH" ]; then
                        "$PORTS_LAUNCH" "$ROM" "$@"
                    else
                        /bin/sh "$ROM" "$@"
                    fi
                else
                    CURRENT_PATH=$(dirname "$ROM")
                    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
                    ROM_PLATFORM=""
                    while [ -z "$ROM_PLATFORM" ]; do
                        [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
                        ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
                        [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
                    done
                    if [ -d "/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak" ]; then
                        EMULATOR="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/launch.sh"
                        "$EMULATOR" "$ROM"
                    elif [ -d "/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak" ]; then
                        EMULATOR="/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak/launch.sh"
                        "$EMULATOR" "$ROM"
                    else
                        ./show_message "Game file not found|$ROM" -l a
                    fi
                fi
                SESSION_DURATION=$(cat "$LAST_SESSION_FILE")
                rm -f "$LAST_SESSION_FILE"
                mission_found=0
                for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
                    [ -f "$mission_file" ] && {
                        mission=$(cat "$mission_file")
                        mission_rom=$(echo "$mission" | cut -d'|' -f7)
                        if [ "$ROM" = "$mission_rom" ]; then
                            mission_found=1
                            field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                            if [ "$field_count" -lt 8 ]; then
                                current_accum=0
                            else
                                current_accum=$(echo "$mission" | cut -d'|' -f8)
                            fi
                            new_total=$((current_accum + SESSION_DURATION))
                            if [ "$field_count" -lt 8 ]; then
                                mission=$(echo "$mission" | sed "s/\$/|${SESSION_DURATION}/")
                            else
                                mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                            fi
                            echo "$mission" > "$mission_file"
                            target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                            if [ "$new_total" -ge "$target_seconds" ]; then
                                finalize_mission "$mission_file"
                            fi
                            break
                        fi
                    }
                done
                if [ "$mission_found" -eq 0 ] && [ -f "$BITPAL_DIR/active_mission.txt" ]; then
                    mission=$(cat "$BITPAL_DIR/active_mission.txt")
                    mission_rom=$(echo "$mission" | cut -d'|' -f7)
                    if [ "$ROM" = "$mission_rom" ]; then
                        field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                        if [ "$field_count" -lt 8 ]; then
                            mission=$(echo "$mission" | sed "s/\$/|${SESSION_DURATION}/")
                            new_total=$SESSION_DURATION
                        else
                            current_accum=$(echo "$mission" | cut -d'|' -f8)
                            new_total=$((current_accum + SESSION_DURATION))
                            mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                        fi
                        echo "$mission" > "$BITPAL_DIR/active_mission.txt"
                        target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                        if [ "$new_total" -ge "$target_seconds" ]; then
                            finalize_mission "$BITPAL_DIR/active_mission.txt"
                        fi
                    fi
                fi
            else
                ./show_message "Game file not found|$ROM" -l a
            fi
            ;;
        "bitpal_options")
            options_output=$(./picker "bitpal_options.txt")
            options_status=$?
            [ $options_status -ne 0 ] && continue
            option_action=$(echo "$options_output" | cut -d'|' -f2)
            if [ -x "./bitpal_options/${option_action}.sh" ]; then
                export SELECTED_ITEM="$picker_output"
                export MENU
                export BITPAL_DIR
                export BITPAL_DATA
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                export ACTIVE_MISSIONS_DIR
                export COMPLETED_FILE
                "./bitpal_options/${option_action}.sh"
            fi
            ;;
    esac
done

cleanup
exit 0
