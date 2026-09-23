# spruce/armhf: the shared 32-bit userland

The armhf mirror of `spruce/aarch64`: the one place a library the A30's or the Miyoo Mini family's firmware
lacks is added, LAST on their `LD_LIBRARY_PATH`, so a firmware copy always wins where there is one. Built by the
oakMOSS armhf lane (`scripts/build-armhf-userland.sh`, the arm-a30 toolchain in the `cores-armhf` image: GCC 13.2
against glibc 2.23, the fleet's armhf floor; the zlib build dependency is the fleet-minimum 1.2.8).

| file | who asks for it | note |
| --- | --- | --- |
| `lib/libncurses.so.5` | `spruce/bin/nano` (asks for ABI 5 by name) | ncurses 6.5 built `--with-abi-version=5`, terminfo merged in, narrow chars; needs GLIBC_2.17 |
| `lib/libsmartcols.so.1` | `spruce/bin/rfkill` (util-linux) | util-linux 2.39.4, every program off, only this library on; needs GLIBC_2.17 |

Neither soname exists on any armhf rootfs in the lab (fleet census 2026-09-23), so on the A30 and both Mini
models nano and rfkill were the only spruce binaries whose libraries nothing provided. Only these two files ship
from the lane's 26 for now; `SHA256SUMS` lists what is here, `BUILD-INFO` is the lane build's.
