#!/bin/sh
# Overlays the muOS glibc 2.38 (shared with the Flip) onto the TrimUI 2.33 rootfs,
# plus what PortMaster runtimes expect from a newer base. Only /run is written to the rootfs.
# Binds go through the static busybox so no exec runs with a half-swapped libc.

FLIP=/mnt/SDCARD/spruce/flip
SQSH=$FLIP/muOS-pixie-reduced.sqsh
MUOS=$FLIP/muOS
BB=/mnt/SDCARD/spruce/bin64/busybox

if [ -f "$SQSH-partaa" ]; then
    rm -f "$SQSH"
    cat "$SQSH"-part* > "$SQSH" && rm "$SQSH"-part*
fi
[ -f "$SQSH" ] || exit 1

mkdir -p "$MUOS"
grep -q " $MUOS " /proc/mounts || mount -t squashfs "$SQSH" "$MUOS" || exit 1
[ -f /lib/libc-2.33.so ] || exit 0

[ -e /run ] || ln -s /var/run /run

# Stock udev has input_id but no rule calling it, so libinput sees untagged devices.
if [ -d /run/udev/rules.d ] && [ ! -e /lib/udev/rules.d/60-input-id.rules ]; then
    printf '%s\n' \
        'ACTION=="remove", GOTO="id_input_end"' \
        'SUBSYSTEM=="input", ENV{ID_INPUT}=="", IMPORT{builtin}="input_id"' \
        'LABEL="id_input_end"' > /run/udev/rules.d/60-input-id.rules
    udevadm control --reload
    udevadm trigger --subsystem-match=input --action=change
fi

# Older stock firmware keeps SDL2 only in /usr/trimui/lib; ports expect /usr/lib.
# A tmpfs-backed overlay adds links without writing to the rootfs.
if [ ! -e /usr/lib/libSDL2-2.0.so.0 ] && [ -e /usr/trimui/lib/libSDL2-2.0.so.0 ]; then
    OVL=/tmp/usrlib_overlay
    mkdir -p $OVL/upper $OVL/work
    for f in /usr/trimui/lib/libSDL2*.so*; do
        ln -sf "$f" "$OVL/upper/${f##*/}"
    done
    ln -sf /usr/trimui/lib/libSDL2-2.0.so.0 $OVL/upper/libSDL2.so
    $BB mount -t overlay overlay -o lowerdir=/usr/lib,upperdir=$OVL/upper,workdir=$OVL/work /usr/lib
fi

bind() {
    [ -e "$2" ] && $BB mount --bind "$MUOS/$1" "$2"
}

bind lib/libc.so.6 /lib/libc-2.33.so
bind lib/ld-linux-aarch64.so.1 /lib/ld-linux-aarch64.so.1
bind lib/libm.so.6 /lib/libm-2.33.so
bind lib/libpthread.so.0 /lib/libpthread-2.33.so
bind lib/libdl.so.2 /lib/libdl-2.33.so
bind lib/librt.so.1 /lib/librt-2.33.so
bind lib/libresolv.so.2 /lib/libresolv-2.33.so
bind lib/libutil.so.1 /lib/libutil-2.33.so
bind lib/libanl.so.1 /lib/libanl-2.33.so
bind lib/libcrypt.so.1 /lib/libcrypt-2.33.so
bind lib/libnss_dns.so.2 /lib/libnss_dns-2.33.so
bind lib/libnss_files.so.2 /lib/libnss_files-2.33.so
bind usr/lib/libz.so.1.3.1 /usr/lib/libz.so.1.2.8
for d in /lib /usr/lib; do
    bind lib/libgcc_s.so.1 $d/libgcc_s.so.1
    bind lib/libatomic.so.1.2.0 $d/libatomic.so.1.2.0
    bind usr/lib/libstdc++.so.6.0.32 $d/libstdc++.so.6.0.28
done

touch /tmp/glibc_overlay
