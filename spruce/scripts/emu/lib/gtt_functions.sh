#!/bin/sh

# Requires globals:
#   ROM_FILE
#   GAME
#   EMU_NAME
#
# Provides:
#   record_session_start_time
#   record_session_end_time
#   calculate_current_session_duration
#   update_gtt

export START_TIME_PATH="/tmp/start_time"
export END_TIME_PATH="/tmp/end_time"
export DURATION_PATH="/tmp/session_duration"
export TRACKER_JSON_PATH="/mnt/SDCARD/Saves/spruce/gtt.json"

record_session_start_time() {
    date +%s > "$START_TIME_PATH"
}

record_session_end_time() {
    date +%s > "$END_TIME_PATH"
}

calculate_current_session_duration() {
    START_TIME=$(cat "$START_TIME_PATH")
    END_TIME=$(cat "$END_TIME_PATH")
    DURATION=$(( END_TIME - START_TIME ))
    echo "$DURATION" > "$DURATION_PATH"
}

update_gtt() {
    # Initialize GTT JSON if needed
    if [ ! -f "$TRACKER_JSON_PATH" ] || [ -z "$(cat "$TRACKER_JSON_PATH")" ]; then
        jq -n '{ games: {} }' > "$TRACKER_JSON_PATH"
    fi

	# take care of pesky SDCARD vs sdcard
	ROM_FILE="$(echo "$ROM_FILE" | sed 's|/mnt/sdcard|/mnt/SDCARD|')"

    GTT_GAME_NAME="${GAME%.*} ($EMU_NAME)"
    SESSION_DURATION="$(cat "$DURATION_PATH")"
    END_TIME="$(cat "$END_TIME_PATH")"

    PREVIOUS_PLAYTIME="$(jq --arg game "$GTT_GAME_NAME" -r '.games[$game].playtime_seconds // 0' "$TRACKER_JSON_PATH")"
    NEW_PLAYTIME=$((PREVIOUS_PLAYTIME + SESSION_DURATION))

    OLD_NUM_SESSIONS="$(jq --arg game "$GTT_GAME_NAME" -r '.games[$game].sessions_played // 0' "$TRACKER_JSON_PATH")"
    NEW_NUM_SESSIONS=$((OLD_NUM_SESSIONS + 1))

	# update Game Time Tracker
	tmpfile=$(mktemp)
    jq --arg game "$GTT_GAME_NAME" \
	   --arg rompath "$ROM_FILE" \
       --argjson newTime "$NEW_PLAYTIME" \
       --argjson numPlays "$NEW_NUM_SESSIONS" \
       --arg emu "$EMU_NAME" \
       --argjson lastPlayed "$END_TIME" \
       '.games[$game] += {
	   	   rompath: $rompath,
           console: $emu,
           playtime_seconds: $newTime,
           sessions_played: $numPlays,
           last_played: $lastPlayed
       }' "$TRACKER_JSON_PATH" > "$tmpfile" && mv "$tmpfile" "$TRACKER_JSON_PATH"


	# clean up temp files to prevent accidental cross-pollination
	rm "$START_TIME_PATH" "$END_TIME_PATH" "$DURATION_PATH" 2>/dev/null
}