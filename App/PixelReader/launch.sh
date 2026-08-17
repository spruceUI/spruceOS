#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	export LD_LIBRARY_PATH=$(dirname "$0")/libs32:/mnt/SDCARD/spruce/bin:$LD_LIBRARY_PATH
	export SDL_VIDEODRIVER=dummy
elif [ "$PLATFORM" = "Pixel2" ]; then
	export LD_LIBRARY_PATH=/mnt/SDCARD/spruce/bin64:$LD_LIBRARY_PATH
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "reader" -c "./readerPixel2.gptk" &
else
	export LD_LIBRARY_PATH=$(dirname "$0")/libs:/mnt/SDCARD/spruce/bin64:$LD_LIBRARY_PATH
	# reader links libSDL_ttf-2.0 and libSDL_image-1.2 - SDL 1.2 era - but libs/
	# only carries libSDL-1.2 itself. The other aarch64 devices get those two
	# from their firmware; BaseOS has neither, and nor does the stock Anbernic
	# image, so the loader failed before any code ran.
	#
	# They live in their own libXX/ rather than in libs/ deliberately: libs/ is
	# on the path for every aarch64 device, so adding them there would shadow
	# the firmware copies on Brick, Flip and SmartPro, where a version mismatch
	# could break something that currently works.
	#
	# libwebp.so.6 comes along because this SDL_image links it and the libwebp
	# spruce already ships is SONAME libwebp.so.7 - a different ABI, not a
	# substitute. Its remaining deps resolve already: libfreetype from BaseOS's
	# harvest, libpng16/libjpeg/libtiff from spruce/flip/lib.
	case "$PLATFORM" in
		"Anbernic"*)
			export LD_LIBRARY_PATH=$(dirname "$0")/libXX:$LD_LIBRARY_PATH

			# gptokeyb reads the pad through SDL_GameController, and without a
			# mapping it sees a plain joystick and translates nothing - reader
			# gets no keys and the app looks frozen.
			#
			# Positional rather than the default label-named form: reader.gptk
			# speaks SDL's own vocabulary, where "a" is the South button, and on
			# the other devices SDL gets that from a stock mapping which is
			# positional. The label-named map would put every binding in the
			# .gptk on the wrong physical key.
			export_sdl_gamecontroller_map positional
			;;
	esac
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "reader" -c "./reader.gptk" &
fi

cd $(dirname "$0")

export SCREEN_WIDTH=$DISPLAY_WIDTH
export SCREEN_HEIGHT=$DISPLAY_HEIGHT

sleep 0.6

# reader's libSDL-1.2 is sdl12-compat, so the keys gptokeyb injects arrive
# through SDL2's evdev backend. That SDL2 is built without libudev, and BaseOS
# runs no udevd anyway, so it has no reliable way to discover the virtual
# keyboard gptokeyb creates - the pad worked while the keyboard did not.
#
# SDL_EVDEV_DEVICES names the node outright and skips discovery. The node number
# is not fixed (it is whatever is free when gptokeyb starts, event3 on a CubeXX),
# so find it by the name gptokeyb gives it. Also waits for the device rather than
# trusting the sleep above, since reader must not start before it exists.
case "$PLATFORM" in
	"Anbernic"*)
		if [ -n "$SPRUCE_BASEOS" ]; then
			i=0
			while [ "$i" -lt 20 ]; do
				for d in /sys/class/input/event*; do
					[ -r "$d/device/name" ] || continue
					if [ "$(cat "$d/device/name" 2>/dev/null)" = "Fake Keyboard" ]; then
						export SDL_EVDEV_DEVICES="/dev/input/$(basename "$d")"
						break
					fi
				done
				[ -n "$SDL_EVDEV_DEVICES" ] && break
				i=$((i + 1))
				sleep 0.1
			done
		fi
		;;
esac

if [ "$PLATFORM" = "A30" ]; then
	./reader32 2>log.txt
else
	# reader gets its own SDL2, and only reader. Its libSDL-1.2 is sdl12-compat,
	# so everything - drawing and keys - goes through SDL2 underneath. The
	# mali-fbdev SDL2 in dll-mali draws fine but never delivers the keystrokes
	# gptokeyb injects: its only evdev pump is DUMMY_EVDEV_Poll, wired to the
	# dummy video driver, and reader needs mali because unlike the A30's
	# reader32 it has no framebuffer code of its own. Proven on a CubeXX by
	# reading both devices while pressing buttons - the pad and gptokeyb's
	# virtual keyboard emitted 3984 bytes each, and reader still saw nothing.
	#
	# The stock Anbernic userland carries three different aarch64 SDL2 builds.
	# This is the 2.0.12 one from /usr/lib - the vendor's own - which has both
	# the mali video driver and the generic SDL_EVDEV_Poll rather than the
	# dummy-only pump, and needs nothing beyond libasound, libm and libc, all
	# of which BaseOS harvests.
	#
	# gptokeyb deliberately keeps dll-mali: it needs to *see* the pad, and only
	# that build carries NextUI's H700 joystick classification patch. So the two
	# processes run on different SDL2s, which is why this is scoped to the
	# command rather than exported.
	case "$PLATFORM" in
		"Anbernic"*)
			if [ -n "$SPRUCE_BASEOS" ] && [ -f "$(dirname "$0")/libXX/sdl2/libSDL2-2.0.so.0" ]; then
				LD_LIBRARY_PATH="$(dirname "$0")/libXX/sdl2:$LD_LIBRARY_PATH" ./reader 2>log.txt
			else
				./reader 2>log.txt
			fi
			;;
		*)
			./reader 2>log.txt
			;;
	esac
	kill -9 $(pidof gptokeyb)
fi
