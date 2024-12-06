#!/bin/sh

# This script only sets the dynamic text. The actual handling
# for these controller profiles is done between spruce.cfg and
# standard_launch.sh.

case "$1" in

	"Racing" )
		echo -n "A-ⓧ B-ⓞ L1-ⓧ R1-ⓞ"
		return 0
		;;
	"Racing 2" )
		echo -n "B-ⓧ A-ⓞ R1-ⓧ L1-ⓞ"
		return 0
		;;

	"One-handed" )
		echo -n "A-ⓧ B-ⓞ L1-ⓧ L2-ⓞ"
		return 0
		;;
	"One-handed 2" )
		echo -n "B-ⓧ A-ⓞ L2-ⓧ L1-ⓞ"
		return 0
		;;

	"Doubled" )
		echo -n "A-ⓧ B-ⓞ Y-ⓧ X-ⓞ"
		return 0
		;;
	"Doubled 2" )
		echo -n "B-ⓧ A-ⓞ X-ⓧ Y-ⓞ"
		return 0
		;;
		
	"Steward" )
		echo -n "A-ⓧ B-ⓞ X-Esc SELECT-Mouse"
		return 0
		;;
esac
