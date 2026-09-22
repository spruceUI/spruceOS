# spruce/flip/lib-Flip - libraries only the Miyoo Flip can run

`spruce/flip/lib` is the shared aarch64 library directory: every 64-bit spruce device
has it on `LD_LIBRARY_PATH` and on the port library path, so a library there must load
on the oldest glibc in the fleet (the TrimUI boards' 2.33). These nine were built for the
Flip's glibc 2.38 and need 2.34 to 2.38, so on a TrimUI or H700 unit they either fail to
load or, worse, get picked ahead of a copy that would have worked (measured across the 19
lab units, 2026-09-22). They now live here, and only `Flip.cfg` lists this directory.

| library | needs | who uses it on the Flip |
|---|---|---|
| `libavformat.so.58`, `libavutil.so.56`, `libmp3lame.so.0` | GLIBC_2.38 | the Flip's FFmpeg set (ports, muOS chroot) |
| `libavcodec.so.58` | GLIBC_2.35 | same |
| `libvpx.so.8`, `liblzma.so.5`, `libzstd.so.1` | GLIBC_2.34 | same, `libsystemd` |
| `libvpx.so.7` | GLIBC_2.34 | nothing found; kept with the set |
| `libdecor-0.so.0` | GLIBC_2.34 | SDL's Wayland backend, unused |

Other devices that need these sonames get them elsewhere: ports on the TrimUI, H700 and
MagicX boards from `spruce/aarch64/lib` (built at glibc 2.33), the Miniloong and RGB30
from their own system libraries. Adding a library to `spruce/flip/lib` that needs more
than GLIBC_2.33 fails `unittest/tests/test_library_path_hygiene_contracts.py`.
