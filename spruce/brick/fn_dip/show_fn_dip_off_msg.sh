#!/bin/sh

#assume no jq binary in system

# Label the switch popup by the configured switch action instead of a plain
# "OFF". The active switch action is the script present in /usr/trimui/scene/;
# map its basename to a short label, falling back to "OFF" when unknown.
STATE="OFF"
SCENE_SH=$(ls /usr/trimui/scene/*.sh 2>/dev/null | head -n1)
BASE=$(basename "$SCENE_SH" 2>/dev/null)
case "$BASE" in
    # The LED action is "LED off": switch OFF turns the LEDs back ON, so the
    # popup text is inverted relative to the switch state.
    com.trimui.ledc.sh)                 MSG="LED: ON" ;;
    com.trimui.quiet.sh)                MSG="Quiet: $STATE" ;;
    com.trimui.silent.sh)               MSG="Silent: $STATE" ;;
    com.trimui.joystick.sh|com.trimui.toggle.dpad_joystick.sh) MSG="Joystick: $STATE" ;;
    *)                                  MSG="$STATE" ;;
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
