#!/bin/sh
# Mission History Viewer

MENU="${MENU:-bitpal_menu.txt}"
BITPAL_DIR="${BITPAL_DIR:-./bitpal_data}"
BITPAL_DATA="${BITPAL_DATA:-$BITPAL_DIR/bitpal_data.txt}"
COMPLETED_FILE="${COMPLETED_FILE:-$BITPAL_DIR/completed.txt}"

format_duration() {
    local duration=$1
    if [ $duration -ge 3600 ]; then
        hours=$((duration / 3600))
        mins=$(((duration % 3600) / 60))
        echo "${hours}h ${mins}m"
    elif [ $duration -ge 60 ]; then
        mins=$((duration / 60))
        secs=$((duration % 60))
        echo "${mins}m ${secs}s"
    else
        echo "${duration}s"
    fi
}

format_date() {
    local timestamp=$1
    date -d "@$timestamp" "+%m/%d/%y %H:%M" 2>/dev/null || date -r "$timestamp" "+%m/%d/%y %H:%M" 2>/dev/null
}

if [ -f "$COMPLETED_FILE" ] && [ -s "$COMPLETED_FILE" ]; then
    > /tmp/mission_history.txt
    > /tmp/mission_details.txt
    count=0

    tac "$COMPLETED_FILE" 2>/dev/null | while read line; do
        count=$((count + 1))
        [ $count -gt 20 ] && break

        desc=$(echo "$line" | cut -d'|' -f1)
        start_time=$(echo "$line" | cut -d'|' -f2)
        complete_time=$(echo "$line" | cut -d'|' -f3)
        xp=$(echo "$line" | cut -d'|' -f4)

        short_desc="$desc"
        if [ ${#short_desc} -gt 25 ]; then
            short_desc="${short_desc:0:22}..."
        fi

        start_date=$(format_date "$start_time")
        comp_date=$(format_date "$complete_time")
        duration=$((complete_time - start_time))
        duration_text=$(format_duration "$duration")

        echo "$short_desc [$xp XP]|$count|detail" >> /tmp/mission_history.txt
        echo "$count|$desc|$start_date|$comp_date|$xp|$duration_text" >> /tmp/mission_details.txt
    done

    if [ ! -s "/tmp/mission_history.txt" ]; then
        ./show_message "No mission history found." -l a
        rm -f /tmp/mission_history.txt /tmp/mission_details.txt
        exit 0
    fi

    ./show_message "Mission History|Select a mission to|view details" -l a
    history_choice=$(./picker "/tmp/mission_history.txt" -a "DETAILS" -b "BACK")
    history_status=$?

    if [ $history_status -eq 0 ]; then
        sel=$(echo "$history_choice" | cut -d'|' -f2)
        details=$(grep "^$sel|" /tmp/mission_details.txt)
        if [ -n "$details" ]; then
            desc=$(echo "$details" | cut -d'|' -f2)
            start_date=$(echo "$details" | cut -d'|' -f3)
            comp_date=$(echo "$details" | cut -d'|' -f4)
            xp=$(echo "$details" | cut -d'|' -f5)
            duration_text=$(echo "$details" | cut -d'|' -f6)
            ./show_message "Mission Details|$desc|Started: $start_date|Ended: $comp_date|Duration: $duration_text|XP Earned: $xp" -l a
        fi
    fi

    rm -f /tmp/mission_history.txt /tmp/mission_details.txt
else
    ./show_message "No completed missions yet.|Complete a mission to|build your history!" -l a
fi

exit 0
