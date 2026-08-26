#!/bin/sh

#assume no jq binary in system

# Label the switch popup by the configured switch action instead of a plain
# "OFF". The active switch action is the script present in /usr/trimui/scene/;
# map its basename to a short label, falling back to "OFF" when unknown.
STATE="OFF"

# apply-switch-action writes the chosen action's label here whenever it installs
# one. Preferred over mapping script basenames: the scripts have already been
# renamed once (moved to spruce/scripts/FN_Button), and a rename silently
# degraded this popup to a bare "OFF" with nothing to indicate why.
LABEL_FILE="/tmp/spruce_switch_action_label"
ACTION="$(cat "$LABEL_FILE" 2>/dev/null)"

if [ -z "$ACTION" ]; then
    # Fallback: name it from whichever script is installed. Covers a switch set
    # by the old fn_editor app before apply-switch-action first ran.
    SCENE_SH=$(ls /usr/trimui/scene/*.sh 2>/dev/null | head -n1)
    case "$(basename "$SCENE_SH" 2>/dev/null)" in
        scene-rgb-led.sh|com.trimui.ledc.sh)  ACTION="LED off" ;;
        scene-quiet.sh|com.trimui.quiet.sh)   ACTION="Quiet Mode" ;;
        scene-silent.sh|com.trimui.silent.sh) ACTION="Silent Mode" ;;
        scene-wifi.sh)                        ACTION="WiFi off" ;;
        scene-joystick.sh|spruce_toggle_joystick.sh|com.trimui.joystick.sh|com.trimui.toggle.dpad_joystick.sh)
                                              ACTION="Joystick Toggle" ;;
    esac
fi

case "$ACTION" in
    # "LED off" and "WiFi off" name what the switch turns OFF, so their popup text
    # is inverted relative to the switch state.
    "LED off")         MSG="LED: ON" ;;
    "WiFi off")        MSG="WiFi: ON" ;;
    "Quiet Mode")      MSG="Quiet: OFF" ;;
    "Silent Mode")     MSG="Silent: OFF" ;;
    "Joystick Toggle") MSG="Joystick: OFF" ;;
    *)                 MSG="OFF" ;;
esac

VOL_MSG_JSON="\n\
{ \n\
    \"type\":\"default\", \n\
    \"id\":\"com.trimui.osd.msg.fneditor_dip\", \n\
    \"duration\":1000, \n\
    \"size\":0, \n\
    \"x\":700, \n\
    \"y\":80, \n\
    \"w\":300, \n\
    \"h\":80, \n\
    \"message\":\" $MSG\", \n\
    \"font\":\"\", \n\
    \"bg\":\"\", \n\
    \"icon\":\"/usr/trimui/apps/fn_editor/ic-fn-off-tips.png\", \n\
    \"fontsize\":24, \n\
    \"fontcolor\":\"FFFFFFFF\" \n\
} \n"

echo -e $VOL_MSG_JSON > /tmp/trimui_osd/osd_toast_msg
#echo -e $VOL_MSG_JSON > dump.txt
