#!/bin/sh
# BitPal Status script with improved mood support

MENU="${MENU:-bitpal_menu.txt}"
BITPAL_DIR="${BITPAL_DIR:-./bitpal_data}"
BITPAL_DATA="${BITPAL_DATA:-$BITPAL_DIR/bitpal_data.txt}"
ACTIVE_MISSIONS_DIR="${ACTIVE_MISSIONS_DIR:-$BITPAL_DIR/active_missions}"
COMPLETED_FILE="${COMPLETED_FILE:-$BITPAL_DIR/completed.txt}"

# Function to restore original GameSwitcher settings
restore_game_switcher() {
    local rom_path="$1"
    
    # Get ROM platform
    CURRENT_PATH=$(dirname "$rom_path")
    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
    ROM_PLATFORM=""
    while [ -z "$ROM_PLATFORM" ]; do
         [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
         ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
         [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
    done
    
    # Get config file path
    local rom_name
    rom_name=$(basename "$rom_path")
    local rom_name_clean="${rom_name%.*}"
    local game_config_dir="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/game_settings"
    local game_config="$game_config_dir/$rom_name_clean.conf"
    
    # Check if the file exists and was modified by BitPal
    if [ -f "$game_config" ] && grep -q "#BitPal original=" "$game_config"; then
        # Extract the original setting
        local original_setting
        original_setting=$(grep "#BitPal original=" "$game_config" | sed -E 's/.*#BitPal original=([^ ]*).*/\1/')
        
        if [ "$original_setting" = "NONE" ]; then
            # No previous gameswitcher setting existed, remove the line
            grep -v "^gameswitcher=" "$game_config" > "$game_config.tmp"
            mv "$game_config.tmp" "$game_config"
            
            # If file is empty now, remove it
            if [ ! -s "$game_config" ]; then
                rm -f "$game_config"
            fi
        elif [ "$original_setting" = "NONE_FILE" ]; then
            # File was created by BitPal, remove it entirely
            rm -f "$game_config"
        else
            # Restore the original setting
            sed -i "s|^gameswitcher=OFF #BitPal original=$original_setting|gameswitcher=$original_setting|" "$game_config"
        fi
    fi
}

# Function to restore all game settings from active missions
restore_all_game_settings() {
    # Process all active mission files
    for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
        if [ -f "$mission_file" ]; then
            mission=$(cat "$mission_file")
            rom_path=$(echo "$mission" | cut -d'|' -f7)
            if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
                restore_game_switcher "$rom_path"
            fi
        fi
    done
    
    # Also check legacy mission file
    if [ -f "$BITPAL_DIR/active_mission.txt" ]; then
        mission=$(cat "$BITPAL_DIR/active_mission.txt")
        rom_path=$(echo "$mission" | cut -d'|' -f7)
        if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
            restore_game_switcher "$rom_path"
        fi
    fi
}

# Load BitPal data
[ -f "$BITPAL_DATA" ] && . "$BITPAL_DATA"
[ -z "$name" ] && name="BitPal"
[ -z "$level" ] && level=1
[ -z "$xp" ] && xp=0
[ -z "$xp_next" ] && xp_next=100
[ -z "$mood" ] && mood="happy"
[ -z "$last_visit" ] && last_visit=$(date +%s)
[ -z "$missions_completed" ] && missions_completed=0

# Simple face function
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

face=$(get_face)
active_mission_count=0
[ -d "$ACTIVE_MISSIONS_DIR" ] && active_mission_count=$(find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" | wc -l)

if [ "$active_mission_count" -eq 0 ]; then
    mission_status="No active missions"
elif [ "$active_mission_count" -eq 1 ]; then
    mission_status="1 active mission"
else
    mission_status="$active_mission_count active missions"
fi

# Format the status message (limited to 7 lines max)
status_msg="BitPal Lv.$level - Status|$face|XP: $xp/$xp_next|Mood: $mood|Missions Completed: $missions_completed|$mission_status"
./show_message "$status_msg" -l a

# Try to update background based on mood with random selection
bg_dir="../bitpal_faces"
files=$(ls "$bg_dir"/background_"${mood}"_*.png 2>/dev/null)
if [ -n "$files" ]; then
    set -- $files
    count=$#
    random_index=$((RANDOM % count + 1))
    eval chosen=\$$random_index
    cp "$chosen" "../background.png"
else
    bg_src="$bg_dir/background_${mood}.png"
    [ ! -f "$bg_src" ] && bg_src="$bg_dir/background_happy.png"
    if [ -f "$bg_src" ]; then
        cp "$bg_src" "../background.png"
    fi
fi

echo "Start New Mission|start_mission|option" > /tmp/bitpal_options.txt
[ "$active_mission_count" -gt 0 ] && echo "Manage Missions|manage_missions|option" >> /tmp/bitpal_options.txt
echo "Mission History|mission_history|option" >> /tmp/bitpal_options.txt
echo "Reset BitPal|reset|option" >> /tmp/bitpal_options.txt

option_choice=$(./picker /tmp/bitpal_options.txt -a "SELECT" -b "BACK")
option_status=$?

if [ $option_status -eq 0 ]; then
    option=$(echo "$option_choice" | cut -d'|' -f2)
    case "$option" in
        start_mission)
        ./bitpal_options/start_mission.sh
            ;;
        manage_missions)
        ./bitpal_options/manage_missions.sh
            ;;
        mission_history)
        ./bitpal_options/mission_history.sh
            ;;
        reset)
            ./show_message "Reset BitPal?|This erases all progress,|including level, XP, and|mission history." -l -a "YES" -b "NO"
            if [ $? -eq 0 ]; then
                ./show_message "Are you really sure?|All your BitPal progress|will be permanently lost!" -l -a "YES I'M SURE" -b "CANCEL"
                if [ $? -eq 0 ]; then
                    # Restore all game settings before deleting mission files
                    restore_all_game_settings
                    
                    cat > "$BITPAL_DATA" <<EOF
name=BitPal
level=1
xp=0
xp_next=100
mood=happy
last_visit=$(date +%s)
missions_completed=0
EOF
                    # Try to update background to happy with random selection
                    bg_dir="../bitpal_faces"
                    files=$(ls "$bg_dir"/background_happy_*.png 2>/dev/null)
                    if [ -n "$files" ]; then
                        set -- $files
                        count=$#
                        random_index=$((RANDOM % count + 1))
                        eval chosen=\$$random_index
                        cp "$chosen" "../background.png"
                    else
                        happy_bg="$bg_dir/background_happy.png"
                        if [ -f "$happy_bg" ]; then
                            cp "$happy_bg" "../background.png"
                        fi
                    fi
                    
                    rm -f "$ACTIVE_MISSIONS_DIR"/*.txt "$BITPAL_DIR/active_mission.txt"
                    > "$COMPLETED_FILE"
                    ./show_message "BitPal has been reset.|Back to level 1.|Let the adventure begin anew!" -l a
                fi
            fi
            ;;
    esac
fi

rm -f /tmp/bitpal_options.txt
exit 0