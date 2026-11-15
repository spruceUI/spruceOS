#!/usr/bin/env bash
# Skyscraper for Spruce Scraper at the aarch64 fleet's glibc 2.33 floor (docs/NATIVE-LIBRARIES.md).
#
#   skyscraper/build/fetch-inputs.sh                 # once: the pinned sources, into $INPUTS
#   skyscraper/build/build-glibc233.sh OUT_DIR       # x86_64 Linux, Arm GNU Toolchain 10.3-2021.07
#
# One program with a minimal static Qt 5.15.19 (qtbase: Core, Gui for QImage, Network, Sql, Xml;
# the JPEG and GIF readers) and OpenSSL 3.5.9 linked in. Only what the census found in the
# firmware of every board stays dynamic: glibc (<= 2.33), libstdc++ (<= GLIBCXX_3.4.28), libgcc_s
# (<= GCC_7.0.0) and zlib (built against 1.2.8, the oldest firmware copy). check-floor.py fails the
# build on any other library, any newer symbol version or an rpath.
#
# Environment:
#   TC       the toolchain (default ~/ai/CFW/Spruce/devices/toolchains/arm-gnu-10.3-aarch64)
#   INPUTS   the fetched sources (default ~/ai/cache/sprucescraper-skyscraper-inputs)
#   WORK     build trees (default OUT_DIR/work, removed after a pass; a given WORK must be empty)
#   JOBS     make -j (default: every CPU)
# The host needs bash, make, perl, python3, gcc and g++ (Qt's build tools run on the host), git,
# patch, tar, xz and gzip.
#
# OUT_DIR (empty or new) gets skyscraper/ (build.sh packs it as .scraper/skyscraper), sources/
# (the corresponding source the GPL asks for: the upstream tarballs, Skyscraper's tree, the
# patches and this recipe), BUILD-INFO.txt, SHA256SUMS (every file but itself) and logs/.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
. "$HERE/pins.sh"

die() { echo "build-glibc233: $*" >&2; exit 1; }
step() { echo "== $(date -u +%H:%M:%S) $*"; }
trap 'echo "build-glibc233: FAILED at line $LINENO" >&2' ERR

[ $# -eq 1 ] || die "usage: build-glibc233.sh OUT_DIR"
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
[ -z "$(ls -A "$OUT")" ] || die "OUT_DIR $OUT is not empty"
TC=${TC:-$HOME/ai/CFW/Spruce/devices/toolchains/arm-gnu-10.3-aarch64}
INPUTS=${INPUTS:-$HOME/ai/cache/sprucescraper-skyscraper-inputs}
JOBS=${JOBS:-$(nproc)}
WORK_REAL=${WORK:-$OUT/work}
CROSS=$TC/bin/$TRIPLET-
LOGS=$OUT/logs

# ---- checks before anything is built
[ "$(uname -m)" = x86_64 ] || die "the Arm GNU 10.3 toolchain is x86_64-hosted; this host is $(uname -m)"
[ -x "${CROSS}gcc" ] || die "no toolchain at $TC"
v=$("${CROSS}gcc" -dumpfullversion)
[ "$v" = "$TOOLCHAIN_GCC" ] || die "toolchain GCC is $v, the floor build needs $TOOLCHAIN_GCC"
[ -f "$TC/$TRIPLET/libc/lib64/libc-$TOOLCHAIN_GLIBC.so" ] || die "toolchain sysroot is not glibc $TOOLCHAIN_GLIBC"
for t in make perl python3 gcc g++ git patch tar xz gzip sha256sum; do
    command -v "$t" >/dev/null || die "host lacks $t"
done
for f in "$QT_TARBALL" "$OPENSSL_TARBALL" "$ZLIB_TARBALL" "$SKYSCRAPER_TARBALL"; do
    [ -f "$INPUTS/$f" ] || die "missing $INPUTS/$f: run skyscraper/build/fetch-inputs.sh"
done
while IFS=$'\t' read -r name sum _; do
    case "$name" in '' | '#'*) continue ;; esac
    echo "$sum  $INPUTS/$name" | sha256sum -c --quiet - || die "$name does not match inputs.tsv"
done < "$HERE/inputs.tsv"
got=$( { gzip -dc "$INPUTS/$SKYSCRAPER_TARBALL" 2>/dev/null || true; } | git get-tar-commit-id)
[ "$got" = "$SKYSCRAPER_COMMIT" ] || die "$SKYSCRAPER_TARBALL is commit $got, pins.sh says $SKYSCRAPER_COMMIT"

# Build under a fixed, neutral path: OpenSSL keeps source file names for its error messages, and
# the builder's home directory has no business in the program (as in spruce's userland lane)
[ ! -e "$WORK_REAL" ] || [ -z "$(ls -A "$WORK_REAL")" ] || die "WORK $WORK_REAL is not empty"
BUILD_ALIAS=${BUILD_ALIAS:-/tmp/sprucescraper-skyscraper-build}
[ ! -e "$BUILD_ALIAS" ] || [ -L "$BUILD_ALIAS" ] || die "$BUILD_ALIAS exists and is not a symlink"
mkdir -p "$WORK_REAL" "$LOGS"
ln -sfn "$WORK_REAL" "$BUILD_ALIAS"
W=$BUILD_ALIAS
SRC=$W/src
STAGE=$W/stage
mkdir -p "$SRC" "$STAGE"
# OpenSSL records its compiler command in the library, so the toolchain is reached through the
# alias too; Qt's configure resolves symlinks, so its file names are mapped back to neutral ones
ln -sfn "$TC" "$W/toolchain"
CROSS=$W/toolchain/bin/$TRIPLET-
PREFIX_MAP="-ffile-prefix-map=$WORK_REAL=/build"
export SOURCE_DATE_EPOCH
# Where Qt and OpenSSL think they are installed on the device. Nothing is: Skyscraper loads no
# plugins, and an OPENSSLDIR no device has keeps OpenSSL away from a firmware's openssl.cnf.
NEUTRAL=/opt/sprucescraper

# ---- zlib: the firmware floor, linked against and never shipped
step "zlib $ZLIB_VERSION"
tar -xzf "$INPUTS/$ZLIB_TARBALL" -C "$SRC"
# set -e does not reach into a subshell tested by ||, so every step chains with &&
(
    cd "$SRC/zlib-$ZLIB_VERSION" &&
        CHOST=$TRIPLET CC="${CROSS}gcc" AR="${CROSS}ar" RANLIB="${CROSS}ranlib" CFLAGS="-O2 -fPIC" \
            ./configure --prefix="$STAGE/zlib" &&
        make -j"$JOBS" &&
        make install
) > "$LOGS/zlib.log" 2>&1 || die "zlib failed: logs/zlib.log"
ZLIB_FLOOR=$STAGE/zlib/lib/libz.so.$ZLIB_VERSION
[ -f "$ZLIB_FLOOR" ] || die "zlib built no $ZLIB_FLOOR"

# ---- OpenSSL, static
step "OpenSSL $OPENSSL_VERSION"
tar -xzf "$INPUTS/$OPENSSL_TARBALL" -C "$SRC"
SSL=$STAGE/openssl
OPENSSL_CONFIGURE=(
    linux-aarch64 "--cross-compile-prefix=$CROSS"
    "--prefix=$NEUTRAL/openssl" "--openssldir=$NEUTRAL/openssl/ssl" --libdir=lib
    no-shared no-module no-legacy no-afalgeng no-tests no-zlib -Os
)
(
    cd "$SRC/openssl-$OPENSSL_VERSION" &&
        ./Configure "${OPENSSL_CONFIGURE[@]}" &&
        make -j"$JOBS" build_libs &&
        make DESTDIR="$STAGE/openssl-root" install_dev
) > "$LOGS/openssl.log" 2>&1 || die "OpenSSL failed: logs/openssl.log"
mv "$STAGE/openssl-root$NEUTRAL/openssl" "$SSL"

# ---- Qt: qtbase only, static, with nothing a QCoreApplication that edits images does not use
step "Qt $QT_VERSION (qtbase)"
tar -xJf "$INPUTS/$QT_TARBALL" -C "$SRC"
QTSRC=$SRC/qtbase-everywhere-src-$QT_VERSION
QT=$STAGE/qt5
QT_CONFIGURE=(
    -prefix "$NEUTRAL/qt5" -extprefix "$QT"
    -opensource -confirm-license -release -static -optimize-size -c++std c++17
    -device linux-generic-g++ -device-option "CROSS_COMPILE=$CROSS"
    -no-pkg-config -nomake examples -nomake tests
    # Qt Gui for QImage only: no window system, input, GPU or system fonts
    -no-widgets -no-opengl -no-egl -no-eglfs -no-gbm -no-kms -no-linuxfb -no-directfb -no-xcb
    -no-xcb-xlib -no-xkbcommon -no-vulkan -no-evdev -no-libinput -no-mtdev -no-tslib -no-libudev
    -no-cups -no-fontconfig -qpa minimal
    # third-party code from Qt's own tree, linked in; zlib is the one every firmware has
    -qt-freetype -qt-harfbuzz -qt-pcre -qt-doubleconversion -qt-libpng -qt-libjpeg -no-ico
    -system-zlib "ZLIB_PREFIX=$STAGE/zlib"
    -no-dbus -no-glib -no-icu -no-iconv -no-journald -no-syslog -no-zstd
    -no-sql-db2 -no-sql-ibase -no-sql-mysql -no-sql-oci -no-sql-odbc -no-sql-psql -no-sql-sqlite2
    -no-sql-sqlite -no-sql-tds
    -openssl-linked "OPENSSL_PREFIX=$SSL" "OPENSSL_LIBS=-lssl -lcrypto -ldl -lpthread"
    -no-feature-gssapi -no-libproxy -no-sctp
    # bearer management can call a working Wi-Fi "not accessible" and refuse every request
    -no-feature-bearermanagement
    # the TrimUI boards run Linux 4.9, older than statx(2)
    -no-feature-statx
    "QMAKE_CFLAGS+=$PREFIX_MAP" "QMAKE_CXXFLAGS+=$PREFIX_MAP"
)
mkdir -p "$W/qtbase-build"
(
    cd "$W/qtbase-build" &&
        "$QTSRC/configure" "${QT_CONFIGURE[@]}" &&
        make -j"$JOBS" &&
        make install
) > "$LOGS/qtbase.log" 2>&1 || die "qtbase failed: logs/qtbase.log"
cp "$W/qtbase-build/config.summary" "$LOGS/qtbase-config.summary" 2>/dev/null || true

# ---- Skyscraper
step "Skyscraper $SKYSCRAPER_TAG"
tar -xzf "$INPUTS/$SKYSCRAPER_TARBALL" -C "$SRC"
SKY=$SRC/skyscraper-$SKYSCRAPER_TAG
(
    cd "$SKY" || exit 1
    for p in "$HERE"/patches/*.patch; do
        echo "applying $(basename "$p")"
        patch -p1 --no-backup-if-mismatch < "$p" || exit 1
    done
    # BUNDLE_QRC puts Skyscraper's default config files inside the program, which reads them from
    # there when its PREFIX does not exist on the device; QTPLUGIN.platforms=- leaves out the
    # window system plugin, which a QCoreApplication never loads
    BUNDLE_QRC=1 PREFIX=$NEUTRAL/skyscraper "$QT/bin/qmake" "QTPLUGIN.platforms=-" \
        "QMAKE_CXXFLAGS+=$PREFIX_MAP" skyscraper.pro &&
        make -j"$JOBS" &&
        "${CROSS}strip" --strip-all Skyscraper
) > "$LOGS/skyscraper.log" 2>&1 || die "Skyscraper failed: logs/skyscraper.log"

# ---- the bundle, and the floor gate
step "bundle"
B=$OUT/skyscraper
mkdir -p "$B/data" "$B/licenses/qt"
install -m 755 "$SKY/Skyscraper" "$B/Skyscraper"
cp "$SKY/peas.json" "$SKY/platforms_idmap.csv" "$B/data/"
printf '%s\n' "$BUNDLE_VERSION" > "$B/VERSION"
cp "$SKY/LICENSE" "$B/licenses/Skyscraper-GPL-3.0.txt"
cp "$QTSRC/LICENSE.LGPL3" "$B/licenses/Qt-LGPL-3.0.txt"
cp "$SRC/openssl-$OPENSSL_VERSION/LICENSE.txt" "$B/licenses/OpenSSL-Apache-2.0.txt"
python3 "$HERE/qt-attributions.py" "$QTSRC" "$B/licenses/qt" > "$LOGS/qt-attributions.log"
# run beside the program: BUILD-INFO.txt ships this report, so it names the file without a path
(cd "$B" && python3 "$HERE/check-floor.py" --readelf "${CROSS}readelf" --zlib "$ZLIB_FLOOR" \
    --forbid "$WORK_REAL" --forbid "$OUT" --forbid "$TC" --forbid "$INPUTS" Skyscraper) > "$LOGS/floor.txt" ||
    { cat "$LOGS/floor.txt" >&2; die "the program is above the fleet floor: logs/floor.txt"; }
cat "$LOGS/floor.txt"

# ---- the corresponding source
step "sources"
S=$OUT/sources
mkdir -p "$S/patches" "$S/recipe"
cp "$INPUTS/$QT_TARBALL" "$INPUTS/$OPENSSL_TARBALL" "$INPUTS/$ZLIB_TARBALL" "$INPUTS/$SKYSCRAPER_TARBALL" "$S/"
cp "$HERE"/patches/*.patch "$S/patches/"
cp "$HERE"/{build-glibc233.sh,fetch-inputs.sh,pins.sh,inputs.tsv,check-floor.py,qt-attributions.py} "$S/recipe/"

if RECIPE=$(git -C "$REPO" rev-parse HEAD 2>/dev/null); then
    [ -z "$(git -C "$REPO" status --porcelain -- skyscraper/build)" ] ||
        RECIPE="$RECIPE (skyscraper/build differs from it)"
else
    RECIPE=unknown
fi
{
    echo "# Skyscraper $BUNDLE_VERSION in Spruce Scraper"
    echo
    echo "Skyscraper $SKYSCRAPER_TAG by Lars Muldjord, maintained by Gemba (GPL-3.0), commit"
    echo "$SKYSCRAPER_COMMIT, built $(date -u +%Y-%m-%d) by Spruce Scraper's skyscraper/build/build-glibc233.sh"
    echo "(recipe $RECIPE) as one program with Qt $QT_VERSION (qtbase, LGPL-3.0) and OpenSSL $OPENSSL_VERSION"
    echo "(Apache-2.0) linked in. Spruce Scraper changed Skyscraper with these patches:"
    for p in "$HERE"/patches/*.patch; do echo "- $(basename "$p")"; done
    echo
    echo "The corresponding source is published next to every release that carries this program,"
    echo "as these files (sha256):"
    echo
    (cd "$S" && find . -type f | sort | sed 's#^\./##' | while read -r f; do
        echo "- \`$f\` $(sha256sum "$f" | cut -c1-64)"
    done)
    echo
    echo "BUILD-INFO.txt has the toolchain and every configure line; licenses/ the licence texts."
} > "$B/SOURCE.md"

{
    echo "name=Skyscraper $BUNDLE_VERSION for Spruce Scraper, glibc $TOOLCHAIN_GLIBC floor"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ) on $(uname -srm), $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
    echo "recipe=$RECIPE"
    echo "toolchain=$("${CROSS}gcc" --version | head -1), sysroot glibc $TOOLCHAIN_GLIBC"
    echo "host_cxx=$(g++ --version | head -1)"
    echo "skyscraper=$SKYSCRAPER_TAG $SKYSCRAPER_COMMIT ($SKYSCRAPER_REPO)"
    for p in "$HERE"/patches/*.patch; do echo "patch=$(basename "$p") $(sha256sum "$p" | cut -c1-64)"; done
    for f in "$QT_TARBALL" "$OPENSSL_TARBALL" "$ZLIB_TARBALL" "$SKYSCRAPER_TARBALL"; do
        echo "input=$f $(sha256sum "$INPUTS/$f" | cut -c1-64)"
    done
    echo "zlib=CHOST=$TRIPLET ./configure (CFLAGS -O2 -fPIC): linked against, not shipped"
    # BUILD-INFO.txt ships in the bundle: the build tree's real path is written as <work>
    echo "openssl_configure=${OPENSSL_CONFIGURE[*]}"
    echo "qt_configure=${QT_CONFIGURE[*]//$WORK_REAL/<work>}"
    echo "skyscraper_qmake=BUNDLE_QRC=1 PREFIX=$NEUTRAL/skyscraper qmake QTPLUGIN.platforms=-" \
        "QMAKE_CXXFLAGS+=${PREFIX_MAP//$WORK_REAL/<work>} skyscraper.pro"
    echo
    cat "$LOGS/floor.txt"
} > "$OUT/BUILD-INFO.txt"
cp "$OUT/BUILD-INFO.txt" "$B/BUILD-INFO.txt"
# no shipped file may name the build host's paths (check-floor.py already checked the program)
if grep -r -l -F -e "$WORK_REAL" -e "$OUT" -e "$TC" -e "$INPUTS" "$B" >&2; then
    die "host paths in the bundle: the files above"
fi

# ---- finish: logs compressed, the build tree gone (a failed build keeps it), sums of every file
step "finish"
gzip -n -9 "$LOGS"/*.log
rm -f "$BUILD_ALIAS"
if [ -z "${WORK:-}" ]; then
    rm -rf "$WORK_REAL"
fi
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sort | sed 's#^\./##' | xargs -d '\n' sha256sum > SHA256SUMS)
echo "OK: $OUT/skyscraper ($(du -sh "$B" | cut -f1)), $(wc -l < "$OUT/SHA256SUMS") files in SHA256SUMS"
