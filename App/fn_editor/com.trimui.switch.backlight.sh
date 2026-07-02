#!/bin/sh
LCD_BL=`/usr/trimui/bin/systemval brightness`
LCD_BL_SET=$LCD_BL
SYSTEM_JSON="/mnt/UDISK/system.json"
BACKLIGHT_PATH="/sys/class/backlight/backlight0/brightness"

echo "get brightness:"$LCD_BL

if test $LCD_BL -lt 1; then
  LCD_BL_SET=2
elif test $LCD_BL -lt 3; then
  LCD_BL_SET=5
elif test $LCD_BL -lt 7; then
  LCD_BL_SET=10
else
  LCD_BL_SET=1
fi

case "$LCD_BL_SET" in
  10) LCD_RAW=255 ;;
  9) LCD_RAW=225 ;;
  8) LCD_RAW=200 ;;
  7) LCD_RAW=175 ;;
  6) LCD_RAW=150 ;;
  5) LCD_RAW=125 ;;
  4) LCD_RAW=100 ;;
  3) LCD_RAW=75 ;;
  2) LCD_RAW=50 ;;
  *) LCD_RAW=25 ;;
esac

echo "set brightness:"$LCD_BL_SET
mkdir -p /tmp/system
echo -n $LCD_BL_SET > /tmp/system/set_brightness
echo -n $LCD_RAW > "$BACKLIGHT_PATH"

if [ -f "$SYSTEM_JSON" ]; then
  tmp="$(mktemp)"
  jq ".brightness = $LCD_BL_SET" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON"
fi
