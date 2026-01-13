#!/bin/sh

# Modified From CarlOS launch.sh script

# Allow HOME override via first argument
BASE_HOME="${1:-$HOME}"
ASOUND_CONF="$BASE_HOME/.asoundrc"

is_bluetoothd_running() {
    ps | grep "[b]luetoothd"
}


get_connected_audio_bt_mac() {
    if ! is_bluetoothd_running; then
        return 1
    fi
    for mac in $(bluetoothctl devices | awk '{print $2}'); do
        if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
            name=$(bluetoothctl info "$mac" | grep "Name" | cut -d ' ' -f2-)
            icon=$(bluetoothctl info "$mac" | grep "Icon" | awk '{print $2}')

            if echo "$name" | grep -iqE "headset|speaker|audio|earbud|headphone"; then
                echo "$mac"
                return 0
            fi

            # POSIX-safe test (avoid [[ in /bin/sh)
            if [ "$icon" = "audio-headset" ] || \
               [ "$icon" = "audio-card" ] || \
               [ "$icon" = "audio-headphones" ]; then
                echo "$mac"
                return 0
            fi
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
