# mupen64plus-pow2

One static Mupen64Plus executable for aarch64 retro handhelds: the core, the console front-end and a fixed set of four plugins, linked
together with LTO. No plugin search path, no `.so` files to deploy; `--gfx`, `--audio`, `--input`, `--rsp`, `--plugindir` and `--corelib`
are ignored with a warning. SDL2 stays dynamic (the device's own). Generic armv8-a, `-O3`.

## What Is Inside

- **Core (dento)**: `mupen64plus-core-dento`, our core fork; new arm64 dynarec on aarch64. Built with a built-in plugin table
  (`M64P_STATIC_PLUGINS`), no OSD (suxty draws the menu). Core option of the fork: `Core[RspResumeDelay]` (cycles before a task the RSP plugin left unfinished, one that waits for the
  CPU, is run again on the next SP status write; default 262144, upstream 1000). Gauntlet Legends resumed its task ~800 times per frame at
  1000; with the default 4-6 times, 31.3 -> 20.5 us per primitive on the RK3566. Only a task left unfinished is affected: no other game of
  the sets leaves one. `Core[RspGfxTaskDelay]` (the cycles between the end of a graphics task and its SP interrupt, default 0 = upstream's
  1000) is experimental: it changes the game's pacing, not the cost per primitive, and above 32000 the Rare games (Conker, Jet Force Gemini)
  stop rendering (their RSP watchdog). `Core[RdpFullSyncDelay]` (the cycles between the end of a graphics task and its DP interrupt, i.e.
  the full sync; default 600000, upstream 4000) stands in for the RDP's drawing time: a game that starts its next frame when the last one
  is drawn (Gauntlet Legends draws one per VI with an instant RDP, where the console managed about every second one) paces itself by it.
  The Rare games are unaffected by it (their watchdog is on the SP interrupt). It must stay under one VI (811000): at 900000 every
  60 fps game (Mischief Makers, Dr. Mario, Ridge Racer, Pilotwings, Smash ...) halves its frames; at 600000 none of the 66 games of the
  rgdsplus changed its drawn frames in game, only a few boot sequences and Gauntlet (full speed on the RK3566, 26.8 -> 17.9 ms/VI on
  the H700). `Core[RdpFullSyncDelayMax]` (default 900000) makes it adaptive: while the emulator is behind real time the delay rises
  4000 a VI towards the maximum (the game then draws fewer frames, as it did on a console too slow for it, instead of slow motion) and
  falls back 20000 a second of VIs with slack; a game that keeps up never leaves the minimum. Hot Wheels (race) and the Pokemon Snap
  zoom go from 24-27 ms/VI to full speed at half the frames on both devices; Banjo-Tooie and Mario Tennis are VI-locked at 30 and
  unchanged. A game marginally behind (Pilotwings' intro) hunts between 60 and 30 frames. Max <= Delay makes it fixed, which the
  equivalence harness sets (the delay would otherwise depend on the wall clock).
  With foir (its optional `RdpSyncClocks` export) the delay is no longer a constant: foir estimates the RDP clocks of the commands before
  each full sync from the primitives' shapes (armN64's model: area by cycle type plus setup; foir docs/design.md) and the DP interrupt
  comes `Core[RdpClockScale]` (default 250 %) of that later, rising towards `Core[RdpClockScaleMax]` (400 %) while behind, at the
  same rates as above; `RdpFullSyncDelay(Max)` remain the fallback for plugins without the export and the fixed/adaptive switch.
  Why: a game with two full syncs a frame paid the constant twice (Mario Party 2: 40 fps instead of 60 in its double-sync scenes, 60
  with the estimate). At 250 % Gauntlet's ~325k-clock frames get about the old 600000; F-Zero X, Mario Tennis, Super Mario 64 and Hot
  Wheels' race draw the same frames as with the constant (desktop, 90 s from boot).
  Dynarec (arm64): a block exit through a conditional branch is linked through its stub (upstream left those unlinked because `b.cond`
  reaches only 1 MB, so every taken one called the C linker: 6.7 % of Banjo-Tooie's emulation thread), and the indirect-jump lookup
  reads a compact shadow of the block hash table (one cache line, no list entry to chase: 5.3 -> 2.6 %). Together 34.0 -> 32.2 ms per
  drawn VI in Banjo-Tooie on the RK3566, 36.5 -> 34.7 on the H700; Mario Tennis 30.4 -> 29.4 on the H700. Bit-exact (same code runs).
- **Front-end (inn)**: `mupen64plus-ui-inn`, the console front-end; in bundle mode the core is the executable itself.
- **Video (foir)**: `mupen64plus-rdp-foir`, LLE software RDP, hand-written NEON kernels, order-exact worker threads, no GPU rendering path.
- **RSP (arMLEt)**: `mupen64plus-rsp-armlet`, rsp-hle audio/JPEG/video HLE, native C/NEON graphics for the known ucodes (probe + validated latch for
  unknown ones), parallel-rsp's Lightning JIT as the reference and fallback for everything else, RDP list coalescing.
- **Audio (altru)**: `mupen64plus-audio-altru`, audio-sdl fork: dynamic rate control instead of pause/delay sync, normal-pitch fast-forward,
  automatic buffer size.
- **Input (suxty)**: `mupen64plus-input-suxty`, gamepad-only in-game menu: states, reset, remapping, hotkeys, foir and altru options.

## Layout

| path | content |
|---|---|
| `ext/` | the six components as submodules (`devel` branches) |
| `bundle/` | `build-bundle.sh`, `gen-rename.py`, `check-clashes.py`, generated rename headers and export lists, `stdcxx_compat.cpp` |
| `LICENSES/`, `NOTICE` | licence texts and the per-component table |

## How It Is Linked

- Each plugin builds as a static archive with its own symbol prefix (`foir_`, `armlet_`, `altru_`, `suxty_`, `ui_`): a generated header
  (`-include bundle/rename-<p>.h`) renames its plugin API exports and its `Config*` / `VidExt_*` / `Core*` pointer globals; `check-clashes.py` finds
  the remaining duplicate globals, which go in `bundle/extra-<p>.txt`.
- `plugin.c` in the core resolves the plugin API from a built-in table instead of `dlsym`.
- The executable exports only the core API (`--dynamic-list` + `--version-script`, `bundle/core_api.*`), which the plugins still look up with `dlsym`.
- suxty finds foir's and altru's option interfaces through weak symbols (the `dlopen` scan stays for `.so` builds).

## Build

```sh
git clone --recurse-submodules https://github.com/beebono/mupen64plus-pow2
bundle/build-bundle.sh x86_64                  # desktop, native gcc, scalar foir   -> out/x86_64/mupen64plus-pow2
bundle/build-bundle.sh aarch64                 # Ubuntu aarch64-linux-gnu-* cross   -> out/aarch64/mupen64plus-pow2
bundle/build-bundle.sh rg35xxsp                # (RG35_TOOLCHAIN overrides ../resources/toolchains/rg35xxsp)  glibc 2.31 sysroot, floor check <= 2.17 -> out/rg35xxsp/mupen64plus-pow2
```

- Sources are copied to `work/<target>/` first; `JOBS`, `SDL2_LIBDIR` (aarch64: dir with the device's `libSDL2-2.0.so.0`), `SKIP_LINK=1`,
  `RELINK=1` are the knobs. An LTO link takes 7-10 minutes (mostly serial).
- aarch64 needs the Ubuntu cross toolchain plus cmake/ninja; rg35xxsp uses the host GCC 13 for C (LTO) and g++-12 for parallel-rsp (no LTO, the two
  LTO formats do not mix), with static libstdc++/libgcc from the sysroot. Two small shims in `bundle/stdcxx_compat.cpp` keep the glibc floor at 2.17.
- `vu_inline.cpp` (parallel-rsp, built with the fixed `-ffixed-x*` registers) is kept out of LTO.

## Running

```sh
./mupen64plus-pow2 --configdir <dir> --datadir <core data dir> game.z64
```

- On spruce the process must be called `./mupen64plus`: rename (or copy) `mupen64plus-pow2` at deploy time.
- No OSD from the core; the in-game menu is suxty's.

## Licence

GPL-3.0-or-later as a whole (foir and the arMLEt/Lightning combination are GPL-3 / LGPL-3, the rest is GPL-2.0-or-later). Per-component table in
[NOTICE](NOTICE), texts in [LICENSES/](LICENSES).
