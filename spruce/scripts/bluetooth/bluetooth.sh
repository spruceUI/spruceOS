#!/bin/sh

# Modified From CarlOS launch.sh script

# Allow HOME override via first argument
BASE_HOME="${1:-$HOME}"
ASOUND_CONF="$BASE_HOME/.asoundrc"

BTCTL_TIMEOUT="timeout 2"

get_connected_audio_bt_mac() {
    # Save 2s from the timeout
    if ! pgrep bluetoothd > /dev/null; then
        return 1
    fi

    for mac in $($BTCTL_TIMEOUT bluetoothctl devices 2>/dev/null | awk '{print $2}'); do
        info="$($BTCTL_TIMEOUT bluetoothctl info "$mac" 2>/dev/null)" || continue

        echo "$info" | grep -q "Connected: yes" || continue

        name=$(echo "$info" | grep "Name" | cut -d ' ' -f2-)
        icon=$(echo "$info" | grep "Icon" | awk '{print $2}')

        if echo "$name" | grep -iqE "headset|speaker|audio|earbud|headphone"; then
            echo "$mac"
            return 0
        fi

        if [ "$icon" = "audio-headset" ] || \
           [ "$icon" = "audio-card" ] || \
           [ "$icon" = "audio-headphones" ]; then
            echo "$mac"
            return 0
        fi
    done
    return 1
}


mac=$(get_connected_audio_bt_mac)

if [ -n "$mac" ]; then
    cat > "$ASOUND_CONF" <<EOF
pcm.!default {
    type plug
    slave.pcm {
        type bluealsa
        device "$mac"
        profile "a2dp"
        delay 64
    }
}
ctl.!default {
    type hw
    card 0
}
EOF
else
    [ -f "$ASOUND_CONF" ] && rm "$ASOUND_CONF"
fi
