# spruce/aarch64 - the shared aarch64 userland for the PortMaster port environment

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

`spruce/flip/lib/libdecor-0.so.0` also needs `GLIBC_2.34` and is deliberately
not replaced: it only matters to SDL's Wayland backend, which none of these
devices use.

Added 2026-09-21, from resolving all 46 PortMaster runtime images over the
round-9 dumps of every lab device (`git/spruce-lib-audit`):

| Library | Who needs it | Where it was missing |
|---|---|---|
| `libevdev.so.2` | weston runtime (`libexec_weston` -> `libinput`), 64 ports on the headless path | every H700 unit |
| `libuuid.so.1` | weston's Xwayland (fontconfig); every copy spruce shipped needed `GLIBC_2.38` | every H700 unit |
| `libvorbisfile.so.3`, `libvorbis.so.0`, `libvorbisenc.so.2`, `libogg.so.0` | gmtoolkit's `oggdec` (49 GameMaker ports), rlvm (4) | every MagicX board |
| `libsndfile.so.1` | rlvm | every H700 unit |

## Provenance

`SHA256SUMS` and `BUILD-INFO` record what produced each file. Regenerate with:

```sh
scripts/build-ports-userland.sh          # in the oakMOSS checkout
```
