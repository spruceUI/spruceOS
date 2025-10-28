#!/bin/sh
# Bind all /usr/trimui/lib files into /mnt/SDCARD/brick/sdl2

SRC_DIR="/usr/trimui/lib"
DST_DIR="/mnt/SDCARD/spruce/brick/sdl2"

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
libSDL_image-1.2.so.0 \
libSDL_image-1.2.so.0.8.4 \
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
