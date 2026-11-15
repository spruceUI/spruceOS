# Versions the glibc 2.33 build is pinned to; sourced by fetch-inputs.sh and build-glibc233.sh.
# Tarball checksums are in inputs.tsv. Why these: docs/NATIVE-LIBRARIES.md.
SKYSCRAPER_REPO=${SKYSCRAPER_REPO:-https://github.com/Gemba/skyscraper.git}
SKYSCRAPER_TAG=3.21.1
SKYSCRAPER_COMMIT=ccd49ae99a13ce037476f1d3cc3b646afca2059e
SKYSCRAPER_TARBALL=skyscraper-$SKYSCRAPER_TAG-ccd49ae.tar.gz
BUNDLE_VERSION=$SKYSCRAPER_TAG-spruce1
# the date stamped into the program (OpenSSL's "built on", GCC's __DATE__): the Skyscraper
# commit's (2026-10-11T19:12:56+02:00), so rebuilds do not differ by when they ran
SOURCE_DATE_EPOCH=1791738776

QT_VERSION=5.15.19
QT_TARBALL=qtbase-everywhere-opensource-src-$QT_VERSION.tar.xz
OPENSSL_VERSION=3.5.9
OPENSSL_TARBALL=openssl-$OPENSSL_VERSION.tar.gz
# the oldest zlib any board's firmware serves (TrimUI, stock MagicX); linked against, never shipped
ZLIB_VERSION=1.2.8
ZLIB_TARBALL=zlib-$ZLIB_VERSION.tar.gz

# Arm GNU Toolchain 10.3-2021.07 (aarch64-none-linux-gnu, x86_64 host): GCC 10.3.1, glibc 2.33,
# libstdc++ 6.0.28, the toolchain spruce's 2.33 userland lane uses
TOOLCHAIN_GCC=10.3.1
TOOLCHAIN_GLIBC=2.33
TRIPLET=aarch64-none-linux-gnu
