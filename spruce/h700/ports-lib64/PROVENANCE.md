# spruce/h700/ports-lib64 — audio libraries PortMaster runtimes expect from the OS

## What this is

PortMaster's runtimes (`PortMaster/runtimes/*`) ship the libraries that are
specific to them and expect the host OS to supply the ordinary ones. On every
other spruce device that works: Brick, Flip and SmartPro get them from the
device firmware. **BaseOS has none of them**, so the loader fails before any
port code runs and the port looks like it simply did nothing.

Measured against the love2d 11.5 runtime on an RG CubeXX. `liblove-11.5.so`
resolves everything else from the runtime's own `libs.aarch64`, from
`App/PyUI/dll-mali` or from BaseOS, and is left with exactly these five:

| library | source |
|---|---|
| `libopenal.so.1` | our own `Emu/SCUMMVM/lib` |
| `libvorbisfile.so.3` | our own `Emu/SCUMMVM/lib` |
| `libvorbis.so.0` | our own `Emu/SCUMMVM/lib` (pulled in by `libvorbisfile`) |
| `libmpg123.so.0` | our own `Emu/AMIGA` |
| `libatomic.so.1` | our own `Emu/SCUMMVM/lib` (pulled in by `libopenal`) |

All five are aarch64. They are copies rather than a path entry pointing at those
emulator folders on purpose — see below.

## Why a directory of its own

`Emu/SCUMMVM/lib` holds a whole SDL2 stack, and putting it on the ports path
would shadow the mali SDL2 in `App/PyUI/dll-mali` that is the only build able to
reach this panel. `spruce/h700/lib64` is no good either: it deliberately shadows
`libpng16`, `libtiff`, `libjpeg` and `libwebp` for the SDL 1.2 apps, and ports
must not inherit that. This directory holds only libraries BaseOS is missing
outright, so it can shadow nothing.

`AnbernicXXCommon.cfg` puts it **last** on `PORTS_LD_LIBRARY_PATH`, so if a
later BaseOS ever ships these, its copies win.

## Expect this to grow

Only the love2d runtime has been measured. The other PortMaster runtimes —
godot, solarus, mono and the rest — have their own expectations of the host and
will surface their own gaps as ports get tested on this line. Add them here.

To find what a runtime is missing, trace it rather than running it:

```
LD_TRACE_LOADED_OBJECTS=1 \
LD_LIBRARY_PATH="<runtime>/libs.aarch64:$PORTS_LD_LIBRARY_PATH" \
  /lib/ld-linux-aarch64.so.1 <runtime>/lib<name>.so | grep 'not found'
```
