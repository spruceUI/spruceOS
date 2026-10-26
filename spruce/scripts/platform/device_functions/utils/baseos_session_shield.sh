#!/bin/sh

# Stop BaseOS's respawned session from re-mounting the card during shutdown.
#
# BaseOS's /etc/inittab respawns its session script (/sbin/frontend-session; the
# Anbernic XX line's BaseOS before 1.3.0 named it /sbin/nextui-session), so the moment
# save_poweroff kills the frontend, init starts another one. That script's job
# includes mounting the card if it finds it unmounted, and it cannot tell a
# deliberate shutdown unmount from a yanked card.
#
# Mounting read-write sets the FAT dirty bit. So stage 2 would unmount the card
# cleanly and a second later BaseOS would helpfully mount it straight back, and
# every boot still opened with "Volume was not properly unmounted". Traced end to
# end: clean umount OK, then a session start in the same second.
#
# Bind a shim over it that steps aside while a shutdown is in progress. Same
# technique spruce already uses for /etc/passwd and MainUI, and ephemeral for the
# same reason: nothing is written to BaseOS's rootfs, a BaseOS update can neither
# inherit nor break it, and a reboot removes it entirely. If anything here fails
# we simply leave BaseOS's own script in place.
#
# Usage: shield_baseos_session <session script named in /etc/inittab>
shield_baseos_session() {
    _session="$1"
    _name="${_session##*/}"
    [ -n "$_name" ] && [ -f "$_session" ] || return 0
    # Already shielded where the path resolves now. Binding twice stacks mounts,
    # and device_init can run more than once.
    grep -q "spruce shim over BaseOS" "$_session" 2>/dev/null && return 0

    cp "$_session" "/tmp/$_name.real" 2>/dev/null || return 0
    chmod +x "/tmp/$_name.real" 2>/dev/null

    # Run the shim from /tmp: one started from /usr pins it, and on the BaseOS Flip /usr
    # is an overlay on a card loop (the likely card holder in stage 2's retries, 2026-10-17).
    _bb=/tmp/spruce-shield/busybox _shell=/bin/sh _sleep=sleep
    if [ -x "$_bb" ] || { mkdir -p "${_bb%/*}" && cp /mnt/SDCARD/spruce/bin64/busybox "$_bb" 2>/dev/null &&
        chmod +x "$_bb"; }; then
        "$_bb" true 2>/dev/null && _shell="$_bb sh" _sleep="exec $_bb sleep"
    fi

    cat > "/tmp/$_name.shim" <<SHIM
#!$_shell
# spruce shim over BaseOS's frontend session. Bind-mounted, never installed.
# While a shutdown is in progress the real session must not run: it mounts the
# SD card read-write when it finds it unmounted, which re-dirties the filesystem
# save_poweroff.sh has just unmounted cleanly. The sleep keeps init's respawn
# from becoming a hot loop for the few seconds before the power goes.
if [ -e /tmp/shutting_down.lock ]; then
    $_sleep 5
    exit 0
fi
exec /tmp/$_name.real "\$@"
SHIM
    chmod +x "/tmp/$_name.shim" 2>/dev/null

    if mount -o bind "/tmp/$_name.shim" "$_session" 2>/dev/null; then
        log_message "Shielded BaseOS session script $_session against shutdown remounts"
    else
        log_message "Could not shield BaseOS session script $_session; card may be remounted during shutdown"
    fi
}
