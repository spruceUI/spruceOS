#!/bin/sh

PROFILE="$1"

if [ "$PROFILE" = "Classic" ]; then
	echo -n "C Buttons = R2 + A, B, X, Y"
	return 0

elif [ "$PROFILE" = "Action" ]; then
	echo -n "C Buttons = A, X, Select, R1"
	return 0

else # PROFILE is CUSTOM
	echo -n "User-defined controls"
	return 0
fi