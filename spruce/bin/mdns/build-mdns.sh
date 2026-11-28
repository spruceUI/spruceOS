#!/bin/sh
# Build troglobit mdnsd as static musl binaries for spruce/bin (armhf) and
# spruce/bin64 (aarch64), in an Alpine linux/arm64 Docker container.
#
# Upstream:  https://github.com/troglobit/mdnsd
# Pinned:    commit 18b20c25777d518ac2ec6e7235932f12019866cc (2026-11-15),
#            v1.2 plus 8 commits, including the fix for #99 (probing survives
#            a wall-clock jump, which matters on devices that set the clock
#            from NTP after boot).
# Tarball:   sha256 a6c4cd19c684d211b5e90e7442c8bd9809b12f1b65abb3ad5813a5b6a68c2008
# Patched:   mdnsd-unique-host.patch (next to this script), see README.md
#
# aarch64 is built natively with gcc. armhf is cross-built with clang/lld
# against an Alpine armv7 sysroot (musl-dev + libgcc from Alpine's own armv7
# repo), because Apple Silicon Docker cannot run linux/arm/v7 containers.
# The armhf result is run once under qemu-arm as a sanity check.
#
# Usage: spruce/bin/mdns/build-mdns.sh   (from anywhere; needs Docker)
set -eu

COMMIT=18b20c25777d518ac2ec6e7235932f12019866cc
SHA256=a6c4cd19c684d211b5e90e7442c8bd9809b12f1b65abb3ad5813a5b6a68c2008
ALPINE=alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
mkdir -p "$REPO/spruce/bin/mdns" "$REPO/spruce/bin64/mdns"

CTR=spruce-mdnsd-build
docker rm -f "$CTR" >/dev/null 2>&1 || true
# The patch goes in on stdin: bind mounts are not reliable on every Docker host
docker run -i --name "$CTR" --platform linux/arm64 \
	-e COMMIT="$COMMIT" -e SHA256="$SHA256" "$ALPINE" sh -euc '
	cat > /tmp/mdnsd.patch
	mkdir -p /out32 /out64
	apk add --no-cache build-base autoconf automake libtool pkgconf linux-headers \
		curl clang lld llvm file qemu-arm >/dev/null

	# armv7 sysroot from Alpine packages
	mkdir -p /sysroot/etc/apk
	cp -r /etc/apk/keys /sysroot/etc/apk/
	cp /etc/apk/repositories /sysroot/etc/apk/
	apk add --no-cache --arch armv7 --root /sysroot --initdb \
		musl-dev gcc linux-headers >/dev/null 2>&1

	cd /tmp
	curl -fsSL -o mdnsd.tar.gz "https://github.com/troglobit/mdnsd/archive/$COMMIT.tar.gz"
	echo "$SHA256  mdnsd.tar.gz" | sha256sum -c -

	# $1 = output dir, $2 = strip tool, rest = configure args
	build() {
		out=$1; strip=$2; shift 2
		rm -rf src && mkdir src && tar xzf mdnsd.tar.gz -C src --strip-components=1
		cd src
		patch -p1 < /tmp/mdnsd.patch >/dev/null
		./autogen.sh >/dev/null 2>&1
		./configure --disable-doc --without-systemd --without-mquery \
			--disable-shared --enable-static --runstatedir=/tmp "$@" >/dev/null
		# libtool needs -all-static (plain -static only affects libtool libs);
		# it is passed to make, not configure, which links with the bare compiler
		grep -q "define HAVE_SO_BINDTODEVICE 1" config.h || { echo "no SO_BINDTODEVICE, -i would be missing" >&2; exit 1; }
		make -j"$(nproc)" LDFLAGS="-all-static -Wc,-no-pie" >/dev/null
		bin=src/mdnsd
		[ -f src/.libs/mdnsd ] && bin=src/.libs/mdnsd
		$strip -o "$out/mdnsd" "$bin"
		chmod 755 "$out/mdnsd"
		cd /tmp
	}

	# -fno-strict-aliasing is required: libmdnsd/1035.c _host() passes a
	# char ** as unsigned char ** to short2net(), and at -Os gcc reorders
	# around that and the daemon segfaults on its first probe packet.
	CF="-Os -fno-pie -fno-strict-aliasing"

	build /out64 strip CFLAGS="$CF"

	T=armv7-alpine-linux-musleabihf
	build /out32 llvm-strip --host=$T \
		CC="clang --target=$T --sysroot=/sysroot -fuse-ld=lld -Wno-unused-command-line-argument" \
		CFLAGS="$CF -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard"

	file /out32/mdnsd /out64/mdnsd
	qemu-arm /out32/mdnsd -v | head -1
	/out64/mdnsd -v | head -1
' < "$HERE/mdnsd-unique-host.patch"
docker cp "$CTR:/out32/mdnsd" "$REPO/spruce/bin/mdns/mdnsd"
docker cp "$CTR:/out64/mdnsd" "$REPO/spruce/bin64/mdns/mdnsd"
docker rm "$CTR" >/dev/null
