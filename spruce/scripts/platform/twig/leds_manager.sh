#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# 0 = off
# 1 = on
# 2 = blinking
LEDS_STATE=(0 0 0 0 0)

leds_audio() {
  turn_off_all_leds

  export HOME="/storage"
  cava -p /storage/.config/cava/config | while read value; do
    # echo $value
    if [ $value -lt 25 ] ; then
      turn_off_led 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $value -gt 25 ] ; then
      turn_on_led 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $value -gt 50 ] ; then
      turn_on_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $value -gt 75 ] ; then
      turn_on_led 3
      turn_off_led 4
    fi

    if [ $value -gt 95 ] ; then
      turn_on_led 4
    fi
  done
}

turn_on_led() {
  if [ ${LEDS_STATE[$1]} -eq 0 ] ; then
    echo 1 > /sys/class/leds/led-$1/brightness
    LEDS_STATE[$1]=1
  fi
}

turn_off_led() {
  if [ ${LEDS_STATE[$1]} -eq 1 ] ; then
    echo 0 > /sys/class/leds/led-$1/brightness
    LEDS_STATE[$1]=0
  fi
}

turn_off_all_leds() {
  LEDS_STATE=(1 1 1 1 1)
  for l in 0 1 2 3 4; do
    echo none > "/sys/class/leds/led-$l/trigger"
    turn_off_led $l
  done
}

start_blink(){
  if [ ${LEDS_STATE[$1]} -ne 2 ] ; then
    echo pattern > "/sys/class/leds/led-$1/trigger"
    echo 0 500 1 500 > "/sys/class/leds/led-$1/pattern"
    LEDS_STATE[$1]=2
  fi
}

stop_blink(){
  if [ ${LEDS_STATE[$1]} -eq 2 ] ; then
    echo none > "/sys/class/leds/led-$l/trigger"
    echo 0 > /sys/class/leds/led-$1/brightness
    LEDS_STATE[$1]=0
  fi
}

is_charging(){
  STATUS=$(device_get_charging_status)
  if [ $STATUS = "Charging" ] ; then
    turn_on_led 0
    turn_on_led 1
    start_blink $1
  else
    turn_off_led 0
    stop_blink $1
    turn_on_led $1
  fi
}

leds_battery() {
  LOW_PERCENT="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"

  if [ $LOW_PERCENT = "Off" ] ; then
    LOW_PERCENT=10
  fi

  while true; do
    CAPACITY=$(device_get_battery_percent)

    if [ $CAPACITY -le $LOW_PERCENT ] ; then
      turn_on_led 0
      is_charging 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    elif [ $CAPACITY -gt $LOW_PERCENT ] && [ $CAPACITY -le 25 ] ; then
      is_charging 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    elif [ $CAPACITY -gt 25 ] && [ $CAPACITY -le 50 ] ; then
      stop_blink 1
      turn_on_led 1
      is_charging 2
      turn_off_led 3
      turn_off_led 4
    elif [ $CAPACITY -gt 50 ] && [ $CAPACITY -le 75 ] ; then
      turn_on_led 1
      stop_blink 2
      turn_on_led 2
      is_charging 3
      turn_off_led 4
    elif [ $CAPACITY -gt 75 ] && [ $CAPACITY -le 100 ] ; then
      turn_on_led 1
      turn_on_led 2
      stop_blink 3
      turn_on_led 3
      is_charging 4
    elif [ $CAPACITY -eq 100 ] ; then
      turn_on_led 1
      turn_on_led 2
      turn_on_led 3
      stop_blink 4
      turn_on_led 4
    fi

    sleep 4
  done
}

LEDS_MODE="$(get_config_value '.menuOptions."LEDs Settings".LEDsMode.selected' "Battery")"

case $LEDS_MODE in
  "Battery")
    leds_battery
    ;;
  "Audio")
    leds_audio
    ;;
  *)
    # Off
    turn_off_all_leds
    ;;
esac
