# spruce/aarch64 - the shared aarch64 userland for the PortMaster port environment

> **VARIANT BRANCH `feat/ports-userland-glibc233`: the same 41 files, built at the fleet's ceiling.**
> Everything below describes the set as `feat/trimui-ports-userland` ships it, built with the Tina
> SDK's GCC 6.4 against glibc 2.23 so that no file needs more than `GLIBC_2.17`. On THIS branch the
> same sources and the same recipes were built with Arm GNU Toolchain 10.3-2021.07 (GCC 10.3.1,
> **glibc 2.33**; oakMOSS `PORTS_TOOLCHAIN=armgnu103 scripts/build-ports-userland.sh`), to test on hardware
> what standing on the ceiling costs. 2.33 is the highest floor the aarch64 fleet allows: the four
> TrimUI units run the vendor's glibc 2.33, and anything built against 2.34 or newer cannot start
> there.
>
> What differs: 14 of the 41 files need **exactly `GLIBC_2.33`** - every caller of the `stat` family:
> `cp`, `mv`, `find`, `grep`, `tar`, `unzip`, `sort`, `stat`, `shuf`, `libavformat`, `libavutil`,
> `libbsd`, `libevdev`, `libsndfile` - one needs 2.32 (`liblzma`), and the rest 2.17 to 2.29. That is
> zero margin on a TrimUI unit, and none at all on a Smart Pro still below firmware 1.0.4, which
> shipped glibc 2.29: there these tools sit first on the port `PATH` and cannot start. A 2.33 sysroot
> also makes coreutils call `statx`, which the 4.9 kernels (TrimUI A133P, the XX line, MagicX) do not
> have; the device's glibc is expected to fall back. Both are what this card is for finding out.
> Not a merge candidate. Evidence: `git/spruce-lib-audit/TOOLCHAINS.md`.
>
> **Seven commands the fleet does not have (2026-09-21, this branch only; the 41 files above are
> byte-identical to the first 2.33 build).** Chosen from what PortMaster calls bare, measured against the
> 20 lab device profiles:
>
> | command | absent on | who calls it |
> |---|---|---|
> | `getconf` | every unit | PortMaster's probe-based `device_info.txt` asks it for the glibc version first; its fallback paths miss Debian multiarch, so the seven H700 units would read 0.0.0 and lose every port with a `min_glibc` |
> | `od` | not recorded (BusyBox has the applet on every aarch64 unit; whether a link to it is on the path was not measured) | the same script's first choice for reading a devicetree cell; two ports call it bare |
> | `lscpu` | 19 of 20 | `device_info.txt` 0.1.x - what ships today - sets `DEVICE_CPU` from it |
> | `zramctl` | every unit | eleven ports call it bare |
> | `dos2unix` | the three MagicX boards (the BusyBox applet exists, no link to it) | fifteen ports call it bare |
> | `losetup` | Brick, Brick Pro, Smart Pro | no bare caller in the catalogue; comes free with the util-linux build |
> | `taskset` | 17 of 20 | no bare caller in the catalogue; comes free with the util-linux build |
>
> `getconf` is not built here: it is glibc's own, taken from the Arm GNU 10.3 sysroot. It needs
> `GLIBC_2.17` and libc alone, carries no rpath (the one binary allowed to: it asks for nothing this tree
> ships), and answers from the RUNNING libc, so it reports the device's glibc. The util-linux programs
> link libsmartcols statically, so `lib/` gains nothing; the other six need exactly `GLIBC_2.33`.
> `zip` was checked and needs nothing: `spruce/bin64/zip` is on every aarch64 path, needs `GLIBC_2.17`, and
> its `libbz2.so.1.0` is on every unit or in `spruce/flip/lib` (235 GameMaker ports call `zip -r -0`).
> Left out on purpose: `hexdump`/`xxd`/`strings`/`bc` (BusyBox applets on every aarch64 unit and only
> fallbacks), `jq` (RetroDECK only), `file`, `dialog`, `innoextract`, `readelf`/`ar` (no bare caller).
> The PortMaster APP sees these too: `spruce/portmaster/portmaster.txt` appends `$PORTS_BIN` LAST on its
> path, so it only fills gaps there and never stands in front of a device's own tools.
> **Not run on a device yet.**

Binaries and shared libraries that ports get in front of whatever the device's
stock firmware provides. One set for every aarch64 device; a platform wires it
in from its `.cfg`, and every aarch64 platform that runs PortMaster does:

```sh
export PORTS_BIN="/mnt/SDCARD/spruce/aarch64/bin"
export PORTS_LD_LIBRARY_PATH="/mnt/SDCARD/spruce/aarch64/lib:<the rest>"
```

(Until 2026-09-21 this was `spruce/ports/{bin,lib64}`, wired on the TrimUI units
only. The rename made it the shared set and put it first on the Anbernic XX line
and the MagicX boards too; binaries look for the libraries at `$ORIGIN/../lib`.)

`run_port` puts `$PORTS_BIN` first on the port `PATH`
(`spruce/scripts/emu/lib/ports_functions.sh`), and nothing outside a port run
sees any of it.

## Why this exists

Everything here is built against **glibc 2.23**, with the Tina SDK's own Linaro
GCC 6.4, so every file needs at most `GLIBC_2.17` and loads on every spruce
aarch64 device - the TrimUI units at 2.33 as much as the Miyoo Flip at 2.38.
Build it with `scripts/build-ports-userland.sh` in the oakMOSS repo; that script
carries the pinned source versions, the configure lines and the reasons for
each.

**Do not add a binary here that was built against a newer glibc.** That is the
mistake this directory exists to undo: `spruce/flip/bin/unzip` and
`spruce/flip/lib/liblzma.so.5` need `GLIBC_2.34`, so on the TrimUI devices they
cannot load at all.

## bin - measured breakage this fixes

The stock BusyBox on the TrimUI A133P units is 1.27.2, from 2017.

| Tool | What was broken |
|---|---|
| `env` | `env -u` is rejected. That is how PortMaster starts its message dialog, and **375 ports** call `pm_message`. |
| `unzip` | the port PATH resolved `spruce/flip/bin/unzip`, which cannot load. **44 ports** call it for first-run extraction. |
| `find` | `-quit` (8 ports), `-not`, `-empty`, `-delete` all rejected. |
| `grep` | no `-P` at all; BusyBox has no PCRE. 3 ports use it. |
| `tar` | BusyBox `tar` has no `-z`/`-j`/`-J`. 9 ports extract that way. (GNU tar shells out to `gzip`/`xz`, which are present.) |
| `mv`, `cp`, `sort` | `mv -T` (3 ports), `cp -RT`, `sort -V` rejected. |
| `stat`, `timeout`, `shuf`, `tac`, `sha1sum` | not built into that BusyBox at all. |

## lib - what the rootfs has no usable copy of

Seven of these replace libraries that spruce already ships in
`spruce/flip/lib` but which need `GLIBC_2.34` or newer, so on a glibc-2.33
device they are dead weight that also shadows the working system copy:
`liblzma.so.5`, `libzstd.so.1`, `libmp3lame.so.0`, `libvpx.so.8`,
`libavcodec.so.58`, `libavformat.so.58`, `libavutil.so.56` (plus the rest of the
FFmpeg 4 set: `libswresample`, `libswscale`, `libavfilter`, `libavdevice`,
`libpostproc`).

The others are libraries the CFW compatibility guide asks for and no spruce
device had: `libbsd.so.0` (missing on all four TrimUI units - it is what stopped
frozen-bubble in the sample port runs), `libjpeg.so.62`, `libwebp.so.6` and
`libpcre2-8.so.0` (for `grep -P`).

Since 2026-09-22 `spruce/flip/lib` holds only libraries every 64-bit board can load: the
nine Flip builds that need `GLIBC_2.34` to `2.38` (the FFmpeg set, `liblzma`, `libzstd`,
`libvpx.so.7/.8`, `libdecor`) moved to `spruce/flip/lib-Flip`, which only `Flip.cfg` lists.
The copies here still matter: they are what ports on the TrimUI, H700 and MagicX boards
resolve instead. `unittest/tests/test_library_path_hygiene_contracts.py` keeps the shared
directory at the fleet floor and every board's path free of dead entries.

Added 2026-09-21, from resolving all 46 PortMaster runtime images over the
round-9 dumps of every lab device (`git/spruce-lib-audit`):

| Library | Who needs it | Where it was missing |
|---|---|---|
| `libevdev.so.2` | weston runtime (`libexec_weston` -> `libinput`), 64 ports on the headless path | every H700 unit |
| `libuuid.so.1` | weston's Xwayland (fontconfig); every copy spruce shipped needed `GLIBC_2.38` | every H700 unit |
| `libvorbisfile.so.3`, `libvorbis.so.0`, `libvorbisenc.so.2`, `libogg.so.0` | gmtoolkit's `oggdec` (49 GameMaker ports), rlvm (4) | every MagicX board |
| `libsndfile.so.1` | rlvm | every H700 unit |

Added 2026-09-22, after the dedupe audit and the Pixel 2 firmware study
(`CFW/RootUI/pixel2/PIXEL2-LIBRARIES.md`). From this day `spruce/aarch64/lib` is also the LAST entry of
every 64-bit board's `LD_LIBRARY_PATH` (and of the Flip's port path; first on the Pixel 2's): the firmware
and a board's own directories keep winning, this directory only answers for what none of them have. It is
the one place a library the firmware lacks is added; the prebuilt copies that used to sit in
`spruce/flip/lib`, in Moonlight's `libs` or beside an emulator are gone.

| Library | Who needs it | Where it was missing |
|---|---|---|
| `libboost_filesystem.so.1.71.0` | Emu/SATURN/yabasanshiro | the Pixel 2 (both twigUI firmwares); Development's c977e70dd had moved the only copy into `spruce/flip/lib` |
| `libinterpose.aarch64.so` | the gptokeyb2 in Emu/N64 and Emu/JAGUAR (PortMaster's LD_PRELOAD shim, built from the gptokeyb2 sources) | the Pixel 2 on the classic twigUI firmware; 6e35f2219 had left the only copy in `spruce/flip/lib` |
| `libpulse.so.0`, `libpulse-simple.so.0`, `libpulsecommon-13.99.so` | App/Moonlight's `moonlight` (links the Ubuntu 20.04 pulse client) | the Pixel 2: the Ubuntu copies sat in `spruce/flip/lib` (and `libpulse.so.0` again in Moonlight's own `libs`), which it never lists. One set here now, client libraries only, needing nothing beyond this lane's libsndfile (speexdsp and ltdl satisfy its configure and are not shipped); the Ubuntu copies are retired |
| `libssl.so.1.1`, `libcrypto.so.1.1` | `spruce/bin64/wget`, `spruce/flip/lib`'s `libcurl.so.4` and `libzip.so.5` | the H700 BaseOS and both twigUI firmwares carry OpenSSL 3 on the path |
| `libpcre.so.1` | `spruce/bin64/wget`, Emu/SCUMMVM's glib | twigUI-next, the H700 BaseOS (pcre3 only) |
| `libncursesw.so.6`, `libtinfo.so.6` | `spruce/bin64/rnano` (Emu/N64's own `libncurses.so.6` needs the tinfo half) | the TrimUI, Flip and Miniloong rootfs and the classic twigUI firmware |

Second pass the same day, from a fleet census of every launchable card binary over the 19 lab dumps
(`fleet-missing.py`, kept with the audit kit): the sonames no firmware in the fleet could satisfy.

| Library | Who needs it | Where it was missing |
|---|---|---|
| `libfluidsynth.so.3`, `libharfbuzz.so.0`, `libspeexdsp.so.1` | the EasyRPG core (`cores64/easyrpg_libretro.so`) | every TrimUI, Flip, Miniloong and MagicX unit; only `Emu/EASYRPG/lib-Flip` carried Ubuntu copies, and only the Flip lists that directory. fluidsynth is synth-only (no drivers) and needs just glib |
| `libglib-2.0.so.0`, `libgthread-2.0.so.0`, `libfreetype.so.6` | fluidsynth, harfbuzz and SDL_ttf above | (dependencies of the lane's own libraries; every rootfs has freetype and glib, which keep winning) |
| `libSDL-1.2.so.0`, `libSDL_image-1.2.so.0`, `libSDL_ttf-2.0.so.0` | `App/Gallery/gallery64`, `App/PixelReader/reader` | the three MagicX boards have no SDL 1.2 at all; the others have theirs, which win |

## Provenance

`SHA256SUMS` and `BUILD-INFO` record what produced each file. Regenerate with:

```sh
scripts/build-ports-userland.sh          # in the oakMOSS checkout
```

## Floor rule (2026-09-23)

The firmware serves its own zlib and freetype ahead of this directory on every board that has them, and the
oldest copies in the fleet are zlib 1.2.8 and freetype 2.6.1 (Brick, Brick Pro, Smart Pro, XU20, Zero 28,
Zero 40). So the lane compiles and links against exactly those: zlib 1.2.8 is its build dependency and a
freetype 2.6.1 is staged before harfbuzz and SDL_ttf are built (the shipped freetype 2.10.4 is built last).
Two lane gates enforce it on every shipped file: no ZLIB_ version beyond 1.2.8's, no FT_ import that 2.6.1
lacks. Found by the device verifier's symbol pass: the previous harfbuzz imported FT_Get_Var_Blend_Coordinates
and FT_Done_MM_Var, which loaded fine on those six boards and would have killed the EasyRPG core at the first
variable font. Build 20260923-1443-ports-userland-glibc233-floor; 11 of the 77 files changed.
