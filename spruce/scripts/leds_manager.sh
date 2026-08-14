#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LEDS_STATE=(false false false false false)

leds_audio() {
  turn_off_led 0

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
  if ! ${LEDS_STATE[$1]} ; then
    echo 1 > /sys/class/leds/led-$1/brightness
    LEDS_STATE[$1]=true
  fi
}

turn_off_led() {
  if ${LEDS_STATE[$1]} ; then
    echo 0 > /sys/class/leds/led-$1/brightness
    LEDS_STATE[$1]=false
  fi
}

leds_battery() {
  LOW_PERCENT="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"

  while true; do
    CAPACITY=$(device_get_battery_percent)
    STATUS=$(device_get_charging_status)

    if [ "$STATUS" = "Charging" ] ; then
      turn_on_led 0
      turn_on_led 1
    else
      turn_off_led 0
    fi

    if [ $CAPACITY -le $LOW_PERCENT ] ; then
      turn_on_led 0
      turn_off_led 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $CAPACITY -gt $LOW_PERCENT ] ; then
      turn_on_led 1
      turn_off_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $CAPACITY -gt 25 ] ; then
      turn_on_led 1
      turn_on_led 2
      turn_off_led 3
      turn_off_led 4
    fi

    if [ $CAPACITY -gt 50 ] ; then
      turn_on_led 1
      turn_on_led 2
      turn_on_led 3
      turn_off_led 4
    fi

    if [ $CAPACITY -gt 75 ] ; then
      turn_on_led 1
      turn_on_led 2
      turn_on_led 3
      turn_on_led 4
    fi

    sleep 10
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
    turn_off_led 0
    turn_off_led 1
    turn_off_led 2
    turn_off_led 3
    turn_off_led 4
    ;;
esac