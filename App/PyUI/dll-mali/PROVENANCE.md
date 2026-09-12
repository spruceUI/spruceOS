# App/PyUI/dll-mali

SDL2 and companion libraries used when spruce runs on **BaseOS**
(github.com/pvaibhav/BaseOS) on the Anbernic RG XX (Allwinner H700) devices.

BaseOS has no libdrm/libgbm and no wayland, so our usual KMSDRM/wayland SDL2
cannot reach the panel. This directory is a copy of `../dll` with the SDL2
swapped for a **mali-fbdev** build and two extra dependencies added.
`App/PyUI/launch.sh` prefers this directory over `../dll` on this device family.

## Contents that differ from ../dll

| file | source | license |
|------|--------|---------|
| `libSDL2-2.0.so.0` / `libSDL2-2.0.so` | mali-fbdev SDL2 2.28.5, built from `JohnnyonFlame/SDL-malifbdev-rot` (`--enable-video-mali`), as shipped in NextUI's H700 release | zlib |
| `libsamplerate.so.0` | hard `NEEDED` of the above; not present in the BaseOS rootfs | BSD-2-Clause |
| `libpng12.so.0` | `libSDL2_image` dlopens it at runtime; BaseOS ships only libpng16 | libpng/zlib |

Everything else is copied unchanged from `../dll`.

## TODO: build our own

These are borrowed binaries (permissively licensed, so redistribution is fine -
consistent with the other prebuilt libs already in this repo). Long term we
should build the SDL2 ourselves in CI from `JohnnyonFlame/SDL-malifbdev-rot`
plus the H700 joystick patch in `LoveRetro/h700-toolchain`
(`support/build-sdl2.sh`, `support/sdl2-h700.patch`), so the version and patches
are ours and do not depend on an external release URL.
