# spruce/h700/lib32 — 32-bit (armhf) runtime for Anbernic RG XX under BaseOS

## What this is

The 32-bit library closure needed to run `ra32.h700` (and 32-bit libretro cores)
on the Allwinner H700 Anbernic handhelds, which run **BaseOS**
(github.com/pvaibhav/BaseOS).

`setup_for_retroarch()` in
`spruce/scripts/platform/device_functions/AnbernicXXCommon.sh` prepends this
directory to `LD_LIBRARY_PATH` whenever `RA_BIN` is a `ra32.*` binary.

## Why spruce ships these rather than BaseOS

BaseOS replaces the stock userland with BusyBox and harvests a short allowlist
of libraries from the user's own stock image (`manifest/harvest.list`). That
list was derived from the ldd closure of NextUI, which is 64-bit, so the only
armhf entries are `ld-linux-armhf.so.3` and `libc.so.6` — harvested so the
vendor bluetooth binary `rtk_hciattach` can run. That binary is also the proof
that the kernel runs aarch32 EL0 at all; the 32-bit gap was never a hardware
limit, only a missing userland.

We asked upstream to widen the harvest (pvaibhav/BaseOS#13) and the answer was
a preference not to grow BaseOS, so spruce carries them. This is consistent
with what spruce already does elsewhere: `spruce/flip/libmali-bifrost-g52-g2p0-gbm.so`,
`Emu/NDS/lib32_Brick/libEGL.so.1`, `spruce/miyoomini/lib/libGLESv2.so`.

## Source

All files copied, with symlinks dereferenced, from the stock Anbernic image:

    RGCUBEXX-V1.0.7-EN16GB-260525.IMG   (GPT partition 5, "rootfs")

  * `/lib/arm-linux-gnueabihf/` — the glibc family and support libraries
  * `/usr/lib32/`              — the Mali stack and SDL2

glibc is **Ubuntu GLIBC 2.35-0ubuntu3**. That matters: `libc.so.6` and the
dynamic loader are deliberately **not** shipped here. The loader path is baked
into each binary's `PT_INTERP` and cannot be overridden by `LD_LIBRARY_PATH`
anyway, and loader and libc must be the same build — so BaseOS owns that pair.
Everything here is from the same 2.35 image family, so it matches the libc
BaseOS harvests from the same source.

## Contents (18 files, 23 MB)

| Library | Size | Notes |
|---|---|---|
| `libmali.so.0` | 14.2 MB | Vendor Mali blob, **fbdev winsys** — references no wayland, gbm or drm, only `/dev/fb`. The 32-bit sibling of the aarch64 blob BaseOS already harvests. |
| `libSDL2-2.0.so.0` | 4.1 MB | Anbernic's own build, SDL 2.0.12. Video drivers are `mali` and `dummy` only. See the input caveat below. |
| `libstdc++.so.6` | 1.5 MB | |
| `libasound.so.2` | 641 KB | |
| `libfreetype.so.6` | 465 KB | |
| `libm.so.6` | 261 KB | glibc 2.35 |
| `libpng16.so.16` | 137 KB | pulled in by freetype |
| `libbrotlicommon.so.1` | 129 KB | pulled in by freetype |
| `libudev.so.1` | 105 KB | linked, but nothing enumerates through it here — see below |
| `libgcc_s.so.1` | 97 KB | |
| `libz.so.1` | 73 KB | |
| `libbrotlidec.so.1` | 29 KB | pulled in by freetype |
| `libpthread.so.0` | 12 KB | glibc 2.35 |
| `libdl.so.2` | 5 KB | glibc 2.35 |
| `librt.so.1` | 5 KB | glibc 2.35 |
| `libEGL.so.1` | 2 KB | shim, links to `libmali.so.0` |
| `libGLESv2.so.2` | 2 KB | shim, links to `libmali.so.0` |
| `libGLESv1_CM.so.1` | 2 KB | shim; not referenced by RetroArch, kept for cores and ports that want GLES1 |

Verified: every file is `ELF 32-bit ARM`, and every `SONAME` matches its
filename. The full recursive closure of `ra32.h700` resolves against this
directory plus BaseOS's two armhf entries, with nothing unresolved.

## Known caveat: input

The bundled SDL2 **dlopens `libudev.so.1`**, so its joystick enumeration finds
nothing on BaseOS, which runs no udevd. This is the same wall RetroArch's own
udev input driver hits. RetroArch's `linuxraw` joypad driver reads legacy
`/dev/input/js*` and does not care, but it numbers buttons in kernel
registration order — matching neither the udev nor the sdl2 profile — so it
needs its own autoconfig, captured with
`spruce/scripts/probe_linuxraw_joypad.py`.

Worth trying first, since it costs nothing: `SDL_JOYSTICK_DISABLE_UDEV=1` may
push this SDL2 onto its direct `/dev/input` scan and make the existing sdl2
profile work as-is.

## Licensing

`libmali.so.0` and the EGL/GLES shims are proprietary Allwinner/ARM vendor
binaries redistributed from the stock device image. Everything else is LGPL
(glibc family, freetype, alsa-lib, udev), zlib (zlib, libpng, SDL2) or
MIT-alike (brotli).
