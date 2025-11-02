INPUT_MODE=1

if [ -e /tmp/trimui_inputd/input_dpad_to_joystick ]
then
    if [ -e /tmp/trimui_inputd/input_no_dpad ]
    then
        INPUT_MODE=3
    else
        INPUT_MODE=1
    fi
fi

echo "get input mode:"$INPUT_MODE

#rm -f /tmp/trimui_inputd/input_no_dpad
#touch /tmp/trimui_inputd/input_dpad_to_joystick

blick1() {
  echo 1 > /sys/class/led_anim/effect_enable
  echo 0 > /sys/class/led_anim/anim_frames_enable 
  echo "FFFFFF " > /sys/class/led_anim/effect_rgb_hex_f1
  echo "FFFFFF " > /sys/class/led_anim/effect_rgb_hex_f2
  echo "1" > /sys/class/led_anim/effect_cycles_f1
  echo "1" > /sys/class/led_anim/effect_cycles_f2
  echo "1000" > /sys/class/led_anim/effect_duration_f1
  echo "1000" > /sys/class/led_anim/effect_duration_f2
  echo "5" > /sys/class/led_anim/effect_f1
  echo "5" > /sys/class/led_anim/effect_f2
}

blick2() {
  echo 1 > /sys/class/led_anim/effect_enable
  echo 0 > /sys/class/led_anim/anim_frames_enable 
  echo "00FF88 " > /sys/class/led_anim/effect_rgb_hex_f1
  echo "00FF88 " > /sys/class/led_anim/effect_rgb_hex_f2
  echo "1" > /sys/class/led_anim/effect_cycles_f1
  echo "1" > /sys/class/led_anim/effect_cycles_f2
  echo "1000" > /sys/class/led_anim/effect_duration_f1
  echo "1000" > /sys/class/led_anim/effect_duration_f2
  echo "6" > /sys/class/led_anim/effect_f1
  echo "6" > /sys/class/led_anim/effect_f2
}

blick3() {
  echo 1 > /sys/class/led_anim/effect_enable
  echo 0 > /sys/class/led_anim/anim_frames_enable 
  echo "FF8800 " > /sys/class/led_anim/effect_rgb_hex_f1
  echo "FF8800 " > /sys/class/led_anim/effect_rgb_hex_f2
  echo "1" > /sys/class/led_anim/effect_cycles_f1
  echo "1" > /sys/class/led_anim/effect_cycles_f2
  echo "1000" > /sys/class/led_anim/effect_duration_f1
  echo "1000" > /sys/class/led_anim/effect_duration_f2
  echo "5" > /sys/class/led_anim/effect_f1
  echo "5" > /sys/class/led_anim/effect_f2
}

case "$INPUT_MODE" in
1 ) 
    echo "set input mode 2"
    rm -f /tmp/trimui_inputd/input_no_dpad
    touch /tmp/trimui_inputd/input_dpad_to_joystick
    blick2
    ;;
2 )
    echo "set input mode 3"
    touch -f /tmp/trimui_inputd/input_no_dpad
    touch /tmp/trimui_inputd/input_dpad_to_joystick
    blick3
    ;;
* )
    echo "set input mode 1"
    rm -f /tmp/trimui_inputd/input_no_dpad
    rm /tmp/trimui_inputd/input_dpad_to_joystick
    blick1
    ;;
esac
