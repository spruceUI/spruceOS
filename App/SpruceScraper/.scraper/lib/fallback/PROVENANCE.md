# lib/fallback

Shared libraries `liblove-11.5.so` links against that the firmware of some boards lacks. `launch.sh`
appends this directory to the END of `LD_LIBRARY_PATH`, so a device's own copy, or one on spruce's
path, always wins; these load only where nothing else has the library. Which boards need which file
comes from the fleet census (`docs/NATIVE-LIBRARIES.md`): only libraries some board's firmware is
missing are here. `libfreetype.so.6` left on 2026-11-04: every board's firmware has one.

Not bundled on purpose: `libSDL2-2.0.so.0` (each platform ships an SDL2 built for its video
driver), `libz`, `libstdc++`, `libgcc_s` and glibc (on every board). `liblove-11.5.so` and
`libluajit-5.1.so.2` live in `../` and are loaded first.

## Where the files come from

All eight are unmodified copies from build record
`CFW/Spruce/devices/builds/20261011-2215-oakmoss-fallback233-2ec6aa0` (job B23, salusa,
2026-10-11): spruce's glibc 2.33 userland lane, oakMOSS `scripts/build-ports-userland.sh` at
2ec6aa06f250eb3d28c4406eb47edc7124c1299e with `PORTS_SET=fallback233 PORTS_TOOLCHAIN=armgnu103`
(Arm GNU Toolchain 10.3-2021.07: GCC 10.3.1, glibc 2.33). The sha256 values below are the record's.

| file | sha256 | needs at most | missing from the firmware of | source | licence |
|---|---|---|---|---|---|
| libopenal.so.1 | fcc8cec1… | GLIBC_2.27, GLIBCXX_3.4.22 | H700 (5 boards), stock MagicX (3) | openal-soft-1.23.1.tar.bz2 (796f4b89…) | LGPL-2.0-or-later |
| libatomic.so.1 | 003b364e… | GLIBC_2.17 | H700; only our libopenal needs it | GCC 10.3 runtime, from the toolchain | GPL-3.0 with GCC Runtime Library Exception |
| libmpg123.so.0 | 90e02dca… | GLIBC_2.33 | H700, stock MagicX | mpg123-1.32.9.tar.bz2 (03b61e40…) | LGPL-2.1 |
| libmodplug.so.1 | 64c6de9d… | GLIBC_2.29, GLIBCXX_3.4 | every board but MagicX on oakMOSS | libmodplug-0.8.9.0.tar.gz (457ca5a6…) | public domain |
| libogg.so.0 | ab38e212… | GLIBC_2.17 | H700, stock MagicX | libogg-1.3.5.tar.xz (c4d91be3…) | BSD-3-Clause |
| libvorbis.so.0 | 89f18b28… | GLIBC_2.29 | H700, stock MagicX | libvorbis-1.3.7.tar.xz (b33cc493…) | BSD-3-Clause |
| libvorbisfile.so.3 | d49fc36e… | GLIBC_2.17 | H700, stock MagicX | libvorbis-1.3.7.tar.xz | BSD-3-Clause |
| libtheoradec.so.1 | 4f33c39a… | GLIBC_2.17 | H700, the Flip, stock MagicX | libtheora-1.1.1.tar.bz2 (b6ae1ee2…) | BSD-3-Clause |

Every file is under the fleet floor (glibc 2.33, GLIBCXX_3.4.28). The lane gives each the rpath
`$ORIGIN`, so a fallback library finds its fallback siblings (libvorbis its libogg, libopenal its
libatomic).

## The two LGPL libraries

They are dynamically linked, so another build dropped in this directory replaces them. Their
source is the two unmodified upstream archives named in `SOURCES.tsv`, with the URL and sha256
of each. The lane cross-compiled them with the toolchain above, then set the rpath to `$ORIGIN`:

```
# OpenAL Soft 1.23.1 (CMake, cross toolchain file for aarch64-none-linux-gnu)
cmake -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_NO_CONFIG_UTIL=ON \
  -DALSOFT_DLOPEN=ON -DALSOFT_REQUIRE_ALSA=ON -DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
  -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF -DALSOFT_BACKEND_SNDIO=OFF \
  -DALSOFT_BACKEND_SOLARIS=OFF -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_WAVE=OFF \
  -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_OBOE=OFF -DALSOFT_BACKEND_OPENSL=OFF

# mpg123 1.32.9
./configure --host=aarch64-none-linux-gnu --prefix=/usr --disable-static --with-audio=dummy \
  --with-cpu=aarch64 --disable-components --enable-libmpg123
```
