# Skyscraper 3.21.1-spruce1: where its source is

`Skyscraper` in this folder is Skyscraper 3.21.1 by Lars Muldjord, maintained by Gemba. It is a
separate program under the GNU General Public License, whatever the licence of the files around
it: its source files say version 2 or any later version, and this build is distributed under
version 3. It was built as one program with Qt 5.15.19 (qtbase, LGPL-3.0) and OpenSSL 3.5.9
(Apache-2.0) linked in, against zlib 1.2.8 (at run time it uses the device's own zlib).
`BUILD-INFO.txt` has the toolchain and every configure line. The licence texts are in `licenses/`
here or, inside spruceOS, in `Licenses/SpruceScraper/` at the root of the card (`Licenses.7z` on a
release card).

Its complete source is these six parts:

| part | where | sha256 |
|---|---|---|
| Skyscraper | https://github.com/Gemba/skyscraper at commit `ccd49ae99a13ce037476f1d3cc3b646afca2059e` (tag `3.21.1`) | the commit id |
| our two changes to it (under Skyscraper's licence) | `source/patches/0001-line-buffered-stdout-and-utf8-file-names.patch` | `71775400c9f8dcf37da17dcf9eebf3cf87f91fa4fe596ebe799734442ab0757e` |
| | `source/patches/0002-ca-certificates-from-ssl-cert-file.patch` | `31c38507f8e1025861d1d71c4c0694899b88d6e29722805ef27bdeb2004a64bd` |
| the build scripts (MIT, Spruce Scraper's) | `source/`: `fetch-inputs.sh` downloads and checks everything in this table, `build-glibc233.sh` builds it; `pins.sh` and `inputs.tsv` hold the versions and checksums | |
| Qt 5.15.19, qtbase | https://download.qt.io/archive/qt/5.15/5.15.19/submodules/qtbase-everywhere-opensource-src-5.15.19.tar.xz | `51e91c73abacab81e64efd01bf95794e79c0e605ad80947a024769f0dd620a32` |
| OpenSSL 3.5.9 | https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz | `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` |
| zlib 1.2.8 (built against, not linked in) | https://zlib.net/fossils/zlib-1.2.8.tar.gz | `36658cb768a54c1d4dec43c3116c27ed893e88b02ecfcb44f2166f9c0b7f2a0d` |

To build it again, on x86_64 Linux with the Arm GNU Toolchain 10.3-2021.07: run
`source/fetch-inputs.sh`, then `source/build-glibc233.sh OUT_DIR` (its first lines say what it
needs).
