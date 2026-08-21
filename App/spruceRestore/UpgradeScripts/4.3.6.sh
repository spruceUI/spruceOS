#!/bin/sh
#
# Flycast save states are not portable between builds of the core.
#
# 4.3.6 replaces the shipped Flycast libretro core with a build from upstream
# v2.6 source. Existing states were written by the previous core and will not
# load into it. That matters more than usual here because the Flycast config
# ships with savestate_auto_load enabled: on the next launch of a Dreamcast
# title, RetroArch would load the stale state automatically, the core would
# fault inside the SH4 recompiler, and the game would appear permanently
# unlaunchable with nothing on screen to explain why.
#
# The states are MOVED ASIDE, not deleted - someone may want to roll back to the
# previous core, and these are the only copy of that progress. The move is a
# rename within the same filesystem, so it costs no additional space and takes
# no time regardless of how many states there are.
#
# Save FILES (.srm) and VMU data are a different format, load fine in both
# cores, and are deliberately left alone.
#
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

STATE_DIR="/mnt/SDCARD/Saves/states/Flycast"
BACKUP_DIR="/mnt/SDCARD/Saves/states/Flycast.pre-4.3.6"

if [ ! -d "$STATE_DIR" ]; then
    log_message "4.3.6: no Flycast state directory, nothing to do"
    exit 0
fi

count=$(find "$STATE_DIR" -maxdepth 1 -type f -name '*.state*' 2>/dev/null | wc -l)
if [ "$count" -eq 0 ]; then
    log_message "4.3.6: no Flycast save states to move"
    exit 0
fi

# Never overwrite an existing backup: dev and tester builds re-run same-version
# upgrade scripts, and a second pass must not bury the original set.
if [ -d "$BACKUP_DIR" ]; then
    suffix=1
    while [ -d "${BACKUP_DIR}.${suffix}" ]; do
        suffix=$((suffix + 1))
    done
    BACKUP_DIR="${BACKUP_DIR}.${suffix}"
fi

if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    log_message "4.3.6: could not create $BACKUP_DIR - leaving states in place"
    log_message "4.3.6: WARNING auto-resume may crash Dreamcast titles until these are moved"
    exit 0
fi

moved=0
for f in "$STATE_DIR"/*.state*; do
    [ -f "$f" ] || continue
    if mv -f "$f" "$BACKUP_DIR/" 2>/dev/null; then
        moved=$((moved + 1))
    else
        log_message "4.3.6: failed to move $(basename "$f")"
    fi
done

cat > "$BACKUP_DIR/README.txt" <<'NOTE'
Flycast save states from before the 4.3.6 update.

The Flycast core was replaced in 4.3.6 with a build from upstream v2.6 source.
Save states are tied to the exact core build that wrote them, so these will not
load into the new core - the emulator crashes rather than reporting an error,
which is why they were moved out of the way automatically.

They are kept here in case you roll back to the previous core. If you do, move
them back to:

    /mnt/SDCARD/Saves/states/Flycast/

Otherwise this folder can be deleted at any time. In-game saves (.srm) and VMU
data are not affected and were left where they are.
NOTE

log_message "4.3.6: moved $moved Flycast save state(s) to $BACKUP_DIR (not deleted)"
sync
exit 0
