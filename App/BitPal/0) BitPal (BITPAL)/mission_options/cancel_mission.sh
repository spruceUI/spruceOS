#!/bin/sh
cd "$(dirname "$0")/.."
BITPAL_DIR="${BITPAL_DIR:-./bitpal_data}"
BITPAL_DATA="${BITPAL_DATA:-$BITPAL_DIR/bitpal_data.txt}"
ACTIVE_MISSION="${ACTIVE_MISSION:-$BITPAL_DIR/active_mission.txt}"
ACTIVE_MISSIONS_DIR="${ACTIVE_MISSIONS_DIR:-$BITPAL_DIR/active_missions}"
FACE_DIR="./bitpal_faces"

[ -f "$BITPAL_DATA" ] && . "$BITPAL_DATA"

get_face() {
    case "$mood" in
        excited)    echo "(^o^)" ;;
        happy)      echo "(^-^)" ;;
        neutral)    echo "(-_-)" ;;
        sad)        echo "(;_;)" ;;
        angry)      echo "(>_<)" ;;
        surprised)  echo "(O_O)" ;;
        *)          echo "(^-^)" ;;
    esac
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
         local bg_src="$bg_dir/background_${mood_to_use}.png"
         [ -f "$bg_src" ] && cp "$bg_src" "./background.png"
    fi
}

face=$(get_face)

if [ -z "$ACTIVE_MISSION" ] || [ ! -f "$ACTIVE_MISSION" ]; then
    if [ -d "$ACTIVE_MISSIONS_DIR" ] && [ "$(find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" | wc -l)" -gt 0 ]; then
        > /tmp/cancel_mission_list.txt
        for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
            if [ -f "$mission_file" ]; then
                mission=$(cat "$mission_file")
                mission_desc=$(echo "$mission" | cut -d'|' -f1)
                mission_num=$(basename "$mission_file" | sed 's/mission_\(.*\)\.txt/\1/')
                echo "Mission $mission_num: $mission_desc|$mission_file" >> /tmp/cancel_mission_list.txt
            fi
        done

        ./show_message "$face|Select mission to cancel:" -l a
        mission_choice=$(./picker "/tmp/cancel_mission_list.txt" -a "SELECT" -b "BACK")
        picker_status=$?

        if [ $picker_status -ne 0 ]; then
            rm -f /tmp/cancel_mission_list.txt
            exit 0
        fi

        ACTIVE_MISSION=$(echo "$mission_choice" | cut -d'|' -f2)
        rm -f /tmp/cancel_mission_list.txt
    else
        ./show_message "$face|No active mission.|There is no mission to cancel." -l a
        exit 0
    fi
fi

if [ -f "$ACTIVE_MISSION" ]; then
    mission=$(cat "$ACTIVE_MISSION")
    desc=$(echo "$mission" | cut -d'|' -f1)
    ./show_message "$face|Cancel Mission?|$desc|Are you sure you want|to cancel this mission?" -l -a "YES" -b "BACK"
    if [ $? -eq 0 ]; then
        rom_path=$(echo "$mission" | cut -d'|' -f7)
        if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
            restore_game_switcher "$rom_path"
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

        rm -f "$ACTIVE_MISSION" "/tmp/bitpal_plays_start.txt" "/tmp/bitpal_time_start.txt"

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

        if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
            ./show_message "$face|Didn't like that game?|Delete it from|your device?" -l -a "DELETE" -b "KEEP"
            if [ $? -eq 0 ]; then
                ./show_message "$face|WARNING: PERMANENT ACTION|This will permanently delete|the game from your SD card.|Are you absolutely sure?" -l -a "YES, DELETE IT" -b "NO, KEEP IT"
                if [ $? -eq 0 ]; then
                    rm -f "$rom_path"
                    ./show_message "$face|Game deleted!|Gone forever!" -l a
                else
                    ./show_message "$face|Game kept safe!|Maybe it'll grow on you|with more playtime." -l a
                fi
            fi
        fi
    fi
else
    ./show_message "$face|No active mission.|There is no mission to cancel." -l a
fi

exit 0