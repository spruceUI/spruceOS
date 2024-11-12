#!/bin/sh

P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"

if [ "$1" = "Steward" ]; then
	echo -n "A->(o); B->(x); X->(pause); SELECT->(mouse)"


elif [ "$1" = "Doubled" ]; then
	echo -n "A->(o); B->(x); Y->(o); X->(x)"
	cp -f "$P8_DIR/sdl_controllers.facebuttons" "$P8_DIR/sdl_controllers.txt"


elif [ "$1" = "One-handed"]; then
	echo -n "A->(o); B->(x); L1->(o); L2->(x)"
	cp -f "$P8_DIR/sdl_controllers.onehand" "$P8_DIR/sdl_controllers.txt"


else ### if [ "$1" = "Racing"]; then
	echo -n "A->(o); B->(x); L1->(o); R1->(x)"
	cp -f "$P8_DIR/sdl_controllers.racing" "$P8_DIR/sdl_controllers.txt"


fi