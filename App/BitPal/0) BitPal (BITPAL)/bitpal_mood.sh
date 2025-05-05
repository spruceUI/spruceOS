#!/bin/sh
# Simplified BitPal Mood System

# Function to update BitPal's mood
bitpal_mood() {
    local reason="$1"
    local data="$2"
    # Source the current BitPal data 
    [ -f "$BITPAL_DATA" ] && . "$BITPAL_DATA"
    
    # Store original mood for comparison
    local old_mood="$mood"
    local new_mood="$mood"
    
    # Simple mood update based on reason
    case "$reason" in
        "cancel_mission") new_mood="sad" ;;
        "complete_mission") new_mood="happy" ;;
        "level_up") new_mood="excited" ;;
        "exit") new_mood="sad" ;;
        "reset") new_mood="happy" ;;
        *) new_mood="$mood" ;;
    esac
    
    # Only update if mood changed
    if [ "$new_mood" != "$old_mood" ]; then
        mood="$new_mood"
        # Update BitPal data file with new mood
        if [ -f "$BITPAL_DATA" ]; then
            # Use temp file instead of sed -i
            grep -v "^mood=" "$BITPAL_DATA" > /tmp/bitpal_data_temp
            echo "mood=$new_mood" >> /tmp/bitpal_data_temp
            mv /tmp/bitpal_data_temp "$BITPAL_DATA"
        fi
    fi
}

# Simple face function
get_face() {
    case "$mood" in
        excited)   echo "(^o^)" ;;
        happy)     echo "(^-^)" ;;
        neutral)   echo "(-_-)" ;;
        sad)       echo "(;_;)" ;;
        angry)     echo "(>_<)" ;;
        surprised) echo "(O_O)" ;;
        *)         echo "(^-^)" ;;
    esac
}

# Simple face display
show_bitpal_face() {
    local current_mood="${1:-$mood}"
    local duration="${2:-2}"
    local face_image="$FACE_DIR/${current_mood}.png"
    if [ -f "$face_image" ]; then
        show.elf "$face_image" &
        sleep "$duration"
        killall show.elf 2>/dev/null
    fi
}

# Set background based on mood with random selection
set_background() {
    local mood_to_use="${1:-$mood}"
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
         [ ! -f "$bg_src" ] && bg_src="$bg_dir/background_happy.png"
         [ -f "$bg_src" ] && cp "$bg_src" "./background.png"
    fi
    return 0
}
