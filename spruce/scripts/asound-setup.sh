#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Modified From CarlOS launch.sh script

# Allow HOME override via first argument
BASE_HOME="${1:-$HOME}"
ASOUND_CONF="$BASE_HOME/.asoundrc"

# A device whose userland has no timeout sets BTCTL_TIMEOUT in its
# device_functions file.
BTCTL_TIMEOUT="${BTCTL_TIMEOUT:-timeout 2}"

# From bluez-alsa 4.3 the ALSA plugin switches the headset's codec to each
# client's sample rate, which restarts the A2DP stream, and headsets announce
# that as a disconnect: PyUI opens at 44.1 kHz and games at 48 kHz, so every
# switch between them did it. A device with such a bluealsa sets BT_PCM_RATE
# in its device_functions file; the headset PCM then keeps that rate and plug
# resamples. Older plugins accept only the stream's current rate, so leave it
# unset there.
BT_PCM_FIXED=""
if [ -n "$BT_PCM_RATE" ]; then
    BT_PCM_FIXED="    slave.rate $BT_PCM_RATE
    slave.channels 2
"
fi

mac=$(bt_connected_audio_mac)

mkdir -p "$(dirname "$ASOUND_CONF")"

# A device setting ASOUND_SPRUCE_PCMS writes its speaker as pcm.spruce_speaker.
# Both names are then always defined, so a running PyUI, which read this file
# once at start, can switch between them (AUDIODEV) as the headset comes and goes.
if [ "$ASOUND_SPRUCE_PCMS" = 1 ]; then
    device_write_default_asound_rc
    cat >> "$ASOUND_CONF" <<EOF
pcm.spruce_bt {
    type plug
    slave.pcm {
        type bluealsa
        device "00:00:00:00:00:00"
        profile "a2dp"
        delay 64
    }
${BT_PCM_FIXED}}
pcm.!default {
    type plug
    slave.pcm "$([ -n "$mac" ] && echo spruce_bt || echo spruce_speaker)"
}
EOF
    if [ -n "$mac" ]; then
        command -v device_bt_audio_connected >/dev/null 2>&1 && device_bt_audio_connected
    fi
    device_on_bt_audio_route $mac
elif [ -n "$mac" ]; then
    cat > "$ASOUND_CONF" <<EOF
pcm.!default {
    type plug
    slave.pcm {
        type bluealsa
        device "$mac"
        profile "a2dp"
        delay 64
    }
${BT_PCM_FIXED}}
ctl.!default {
    type hw
    card 0
}
EOF
    command -v device_bt_audio_connected >/dev/null 2>&1 && device_bt_audio_connected
    device_on_bt_audio_route "$mac"
else
    [ -f "$ASOUND_CONF" ] && rm "$ASOUND_CONF"
    device_write_default_asound_rc
    device_on_bt_audio_route
fi
