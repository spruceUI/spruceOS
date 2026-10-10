#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Modified From CarlOS launch.sh script

# Allow HOME override via first argument
BASE_HOME="${1:-$HOME}"
ASOUND_CONF="$BASE_HOME/.asoundrc"

# bluez-alsa 4.3+ restarts the A2DP stream at each client's rate, which headsets
# announce as a disconnect: such a board sets BT_PCM_RATE so plug resamples instead.
# Older plugins accept only the stream's own rate, so leave it unset there.
BT_PCM_FIXED=""
if [ -n "$BT_PCM_RATE" ]; then
    BT_PCM_FIXED="    slave.rate $BT_PCM_RATE
    slave.channels 2
"
fi

mac=$(bt_connected_audio_mac)

mkdir -p "$(dirname "$ASOUND_CONF")"

# With ASOUND_SPRUCE_PCMS, spruce_speaker and spruce_bt are always both defined, so
# a PyUI that read this file once can switch between them through AUDIODEV. The default
# just names one: each has its own plug, and a plug over it aborts alsa-lib 1.2.6.
# A USB card is played to ahead of a headset: a trusted headset reconnects on its own,
# while a card has to be plugged in.
if [ "$ASOUND_SPRUCE_PCMS" = 1 ]; then
    usb=""
    device_usb_audio_supported && usb_audio_card && usb="$usb_card"
    if [ -n "$usb" ]; then
        route=spruce_usb
    elif [ -n "$mac" ]; then
        route=spruce_bt
    else
        route=spruce_speaker
    fi
    device_write_default_asound_rc
    if [ -n "$usb" ]; then
        read -r usb_card usb_dev _ <<EOF
$usb
EOF
        cat >> "$ASOUND_CONF" <<EOF
pcm.spruce_usb {
    type plug
    slave.pcm "hw:$usb_card,$usb_dev"
}
EOF
    fi
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
pcm.!default "$route"
EOF
    # The route is recorded last: usb_audio_watchdog.sh reads it to judge this run.
    if [ "$route" = spruce_usb ]; then
        usb_ctl="$(usb_audio_volume_control "$usb_card")"
        usb_audio_set_volume "$usb_card" "$(get_volume_level)" "$usb_ctl"
        usb_audio_record_route "$usb" "$usb_ctl"
    else
        usb_audio_record_route ""
    fi
    if [ "$route" = spruce_bt ]; then
        device_bt_audio_connected
        device_on_bt_audio_route "$mac"
    else
        device_on_bt_audio_route
    fi
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
    device_bt_audio_connected
    device_on_bt_audio_route "$mac"
else
    [ -f "$ASOUND_CONF" ] && rm "$ASOUND_CONF"
    device_write_default_asound_rc
    device_on_bt_audio_route
fi
