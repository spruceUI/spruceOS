# Create destination directory structure
mkdir -p /mnt/SDCARD/spruce/a30/sdl2/sdl2

# Bind each library file
for f in \
libSDL-1.2.so.0 \
libSDL2-2.0.so.0 \
libSDL2_gfx-1.0.so.0 \
libSDL2_mixer-2.0.so.0 \
libSDL2_ttf-2.0.so.0 \
libSDL_mixer-1.2.so.0 \
libSDL_ttf-2.0.so.0 \
libgamename.so \
libgme.so.1 \
libini.so.0 \
libjpeg.so.8 \
libncursesw.so.6 \
libopk.so.1 \
libpng.so.3 \
libpng12.so.0 \
libpng16.so.16 \
librsautil.so \
libshmvar.so \
libstdc++.so.6 \
libtmenu.so \
libturbojpeg.so.0 \
libunrar.so \
libz.so.1
do
    # Ensure destination file exists
    touch /mnt/SDCARD/spruce/a30/sdl2/$f
    # Bind mount
    mount --bind /usr/miyoo/lib/$f /mnt/SDCARD/spruce/a30/sdl2/$f
done

# Bind the sdl2 subdirectory as well
mount --bind /usr/miyoo/lib/sdl2 /mnt/SDCARD/spruce/a30/sdl2/sdl2
