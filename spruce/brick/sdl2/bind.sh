#!/bin/sh
# Bind all /usr/trimui/lib files into /mnt/SDCARD/brick/sdl2

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

DST_DIR="/mnt/SDCARD/spruce/brick/sdl2"


case "$PLATFORM" in
	Brick|SmartPro)
		SRC_DIR="/usr/trimui/lib"

		# Create destination directory if missing
		mkdir -p "$DST_DIR"

		# List of files to bind
		for f in \
		libSDL-1.2.so.0 \
		libSDL-1.2.so.0.11.4 \
		libSDL2-2.0.so.0 \
		libSDL2-2.0.so.0.3000.8 \
		libSDL2_mixer-2.0.so.0 \
		libSDL2_mixer-2.0.so.0.0.1 \
		libSDL2_ttf-2.0.so.0 \
		libSDL2_ttf-2.0.so.0.14.1 \
		libSDL_mixer-1.2.so.0 \
		libSDL_mixer-1.2.so.0.12.0 \
		libSDL_ttf-2.0.so.0 \
		libSDL_ttf-2.0.so.0.10.1 \
		libgamename.so \
		libshmvar.so \
		libtmenu.so
		do
			# Ensure destination file exists
			touch "$DST_DIR/$f"
			# Bind mount the source file over it
			mount --bind "$SRC_DIR/$f" "$DST_DIR/$f"
		done
		;;
	SmartProS)
		mkdir -p "$DST_DIR"

		for f in \
		/usr/lib/libSDL-1.2.so.0 \
		/usr/lib/libSDL-1.2.so.0.11.4 \
		/usr/lib/libSDL2-2.0.so.0 \
		/usr/lib/libSDL2-2.0.so.0.3200.6 \
		/usr/lib/libSDL2_mixer-2.0.so.0 \
		/usr/lib/libSDL2_mixer-2.0.so.0.2.2 \
		/usr/lib/libSDL2_ttf-2.0.so.0 \
		/usr/lib/libSDL2_ttf-2.0.so.0.18.0 \
		/usr/lib/libSDL_mixer-1.2.so.0 \
		/usr/lib/libSDL_mixer-1.2.so.0.12.1 \
		/usr/lib/libSDL_ttf-2.0.so.0 \
		/usr/lib/libSDL_ttf-2.0.so.0.10.2 \
		/usr/trimui/lib/libgamename.so \
		/usr/trimui/lib/libshmvar.so \
		/usr/trimui/lib/libtmenu.so
		do
			BIND_PATH="$DST_DIR/$(basename "$f")"
			# Ensure destination file exists
			touch "$BIND_PATH"
			# Bind mount the source file over it
			mount --bind "$f" "$BIND_PATH"
		done
		;;
esac
