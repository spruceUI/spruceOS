# spruce/h700/lib64 — aarch64 SDL 1.2-era runtime for Anbernic RG XX

## What this is

The 64-bit library closure needed by the spruce apps that link the **SDL 1.2**
stack — currently the **E-Reader** (`App/PixelReader`) and the **Gallery**
(`App/Gallery`) — on the Allwinner H700 Anbernic handhelds.

Both binaries link `libSDL_image-1.2` and `libSDL_ttf-2.0`. Every app folder
already ships `libSDL-1.2` itself, but not those two: on Brick, Flip and
SmartPro they come from the device firmware. The Anbernic XX line has them in
neither place — **not under BaseOS, and not in the stock Anbernic image** — so
the dynamic loader failed before any application code ran.

## Why here and not in `libs/`

`App/*/libs/` is on `LD_LIBRARY_PATH` for **every** aarch64 device. Several
libraries here deliberately shadow ones spruce already ships, so putting them
there would change what Brick, Flip and SmartPro load and could break devices
that currently work.

Nothing puts this directory on a global path. Only the individual XX app
launchers prepend it, so it is invisible to every other device and to every
other app.

It used to live at `App/PixelReader/libXX/`. The Gallery needs the identical
set, so rather than ship an 8 MB second copy the two apps now share this one.

## Contents and sources

| library | why |
|---|---|
| `libSDL_image-1.2.so.0` | linked by `reader` and `gallery64`; absent from BaseOS and stock |
| `libSDL_ttf-2.0.so.0` | same |
| `libwebp.so.6` | this SDL_image links SONAME `.so.6`; the `libwebp` spruce already ships is `.so.7` — a **different ABI, not a substitute** |
| `libtiff.so.5`, `libjpeg.so.8`, `libpng16.so.16` | see the symbol-version note below |
| `libjbig.so.0`, `libzstd.so.1` | pulled in by `libtiff` |
| `libssl.so.1.1`, `libcrypto.so.1.1` | E-Reader only (`libzip` wants OpenSSL 1.1; BaseOS has 3). Copied from our own `Emu/SCUMMVM/lib`. Harmless to the Gallery, which links neither. |
| `sdl2/libSDL2-2.0.so.0` | see the SDL2 note below |

Sources: **Ubuntu focal arm64** (glibc 2.31, comfortably under BaseOS's 2.35),
except the OpenSSL pair noted above.

## The symbol-version trap

spruce's own `libtiff`/`libjpeg`/`libpng` **define no symbol versions at all**,
while Debian-built consumers such as this `libSDL_image` require `LIBTIFF_4.0`,
`LIBJPEG_8.0` and `PNG16_0`. The first attempt at this failed at load with
`libtiff.so.5: version 'LIBTIFF_4.0' not found` even though a `libtiff.so.5`
was present.

**Presence is not compatibility — check `readelf -V`, not just that the file
exists.** Matching versioned copies live here and, because this directory is
prepended, they win over the unversioned ones in `spruce/flip/lib`.

## The `sdl2/` subdirectory

Both apps' `libSDL-1.2` is **sdl12-compat** — the SDL 1.2 API implemented on top
of SDL2 — so drawing *and* keys go through SDL2 underneath.

The mali-fbdev SDL2 in `App/PyUI/dll-mali` draws fine but never delivers the
keystrokes `gptokeyb` injects: its only evdev pump is `DUMMY_EVDEV_Poll`, wired
to the dummy video driver, and these apps need **mali** because neither has
framebuffer code of its own.

The stock Anbernic userland carries **three** different aarch64 SDL2 builds.
This is the **2.0.12** one from `/usr/lib` — the vendor's own — the only one with
both the mali video driver and the generic `SDL_EVDEV_Poll`. It needs nothing
beyond `libasound`, `libm` and `libc`, all of which BaseOS harvests.

It is applied **scoped to the app's own command line**, never exported:
`gptokeyb` must keep `dll-mali`, because it needs to *see* the pad and only that
build carries NextUI's H700 joystick classification patch. Two processes, two
SDL2s.

## Provided by the OS, not by us

`ld-linux-aarch64.so.1`, `libc`, `libm`, `libdl`, `libpthread`, `libz`,
`liblzma`, `libfreetype` — all present in BaseOS's harvest.
