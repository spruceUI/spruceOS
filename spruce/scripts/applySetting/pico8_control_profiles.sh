#!/bin/sh

# This script only sets the dynamic text. The actual handling
# for these controller profiles is done between spruce.cfg and
# standard_launch.sh.

# Steward
if [ "$1" -eq 3 ]; then
	echo -n "A-ⓧ B-ⓞ X-Esc SELECT-Mouse"
	return 0

# Doubled/Face Buttons
elif [ "$1" -eq 0 ]; then
	echo -n "A-ⓧ B-ⓞ Y-ⓧ X-ⓞ"
	return 0

# One-handed
elif [ "$1" -eq 2 ]; then
	echo -n "A-ⓧ B-ⓞ L1-ⓧ L2-ⓞ"
	return 0

# Racing/Default
else ### if [ "$1" -eq 1 ]; then
	echo -n "A-ⓧ B-ⓞ L1-ⓧ R1-ⓞ"
	return 0
fi