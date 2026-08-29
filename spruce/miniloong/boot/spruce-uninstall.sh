#!/bin/sh
set -u
# Rootfs-side uninstaller for the Miniloong Spruce boot stub. Removes the init
# hook so the device boots stock again; leaves all SD-card content untouched.
HOOK=/etc/init.d/S49spruce
SELF=/usr/bin/spruce-uninstall.sh
LOG="${SPRUCE_UNINSTALL_LOG:-/tmp/spruce-uninstall.log}"

log() { printf '[%s] %s\n' "$(date '+%F %T' 2>/dev/null || echo unknown)" "$*" >>"$LOG" 2>/dev/null || true; }

log "uninstall starting"
mount -o remount,rw / 2>>"$LOG" || mount -o remount,rw /dev/root / 2>>"$LOG" || true
rm -f "$HOOK" 2>/dev/null || true
log "removed $HOOK"
echo "removed Spruce init hook"
rm -f "$SELF" 2>/dev/null || true
sync
