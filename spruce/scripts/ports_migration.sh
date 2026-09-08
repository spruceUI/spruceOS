#!/bin/sh
#
# Roms/PORTS -> Roms/ports, once, on the first boot after an install or update.
#
# Why: every PortMaster launcher computes GAMEDIR=/$directory/ports/<game>,
# where $directory is the ports drive. With the folder named PORTS, spruce had
# to bind Roms/PORTS onto Roms/PORTS/ports on every device to make that
# resolve; the Flip's card is mounted with iocharset=utf8, where FAT lookups
# are case-sensitive, so "ports" could never simply mean "PORTS" there. Naming
# the folder ports removes the bind everywhere.
#
# How it is triggered: spruce/flags/ports_PORTS_migration ships in every
# release and OTA package (all tracked flags do, see the release workflow) and
# spruce/ is re-extracted on every update, so the flag is present exactly once
# after each install or update. runtime.sh runs migrate_ports_dir when it sees
# the flag and deletes it; boots without the flag do nothing at all.
#
# Why it has to be idempotent and run every update: a user extracting a new
# release onto an old card from Windows or macOS gets the archive's Roms/ports
# merged into the existing folder, which keeps its old PORTS name, so the
# rename must be redone; and an OTA extracted on a case-sensitive mount
# creates a lowercase ports (with the shipped Imgs/.gitkeep) next to the old
# PORTS, so the two have to be merged. Both are handled below by looking at
# the folder's STORED name, not testing -d, which answers yes to either
# spelling on a case-insensitive mount.

PORTS_MIGRATION_FLAG=/mnt/SDCARD/spruce/flags/ports_PORTS_migration

# Print the stored spellings of the ports folder under $1: "PORTS", "ports",
# both, or nothing.
ports_dir_names() {
    ls -1 "$1" 2>/dev/null | grep -x 'PORTS\|ports'
}

# Make $1/ports the one and only ports folder under the Roms root $1.
normalize_ports_dir() {
    _root="$1"
    [ -d "$_root" ] || return 0
    _names="$(ports_dir_names "$_root")"
    _has_upper=0; _has_lower=0
    echo "$_names" | grep -qx PORTS && _has_upper=1
    echo "$_names" | grep -qx ports && _has_lower=1

    if [ "$_has_upper" = 0 ]; then
        [ "$_has_lower" = 0 ] && mkdir -p "$_root/ports"
        log_message "Ports migration: $_root/ports already in place" -v
    elif [ "$_has_lower" = 0 ]; then
        # Only PORTS. A case-only mv is refused on a case-insensitive mount and
        # is an ordinary rename on a case-sensitive one; going through a
        # temporary name works on both.
        if mv "$_root/PORTS" "$_root/.ports.migrating" && mv "$_root/.ports.migrating" "$_root/ports"; then
            log_message "Ports migration: renamed $_root/PORTS to ports"
        else
            log_message "Ports migration: FAILED to rename $_root/PORTS"
            return 1
        fi
    else
        # Both spellings exist as separate entries, which only a case-sensitive
        # mount can produce (an OTA extracted the shipped Roms/ports next to
        # the old folder). Fold PORTS into ports: renames within one
        # filesystem, so it takes no time and no space however big the ports.
        merge_dir "$_root/PORTS" "$_root/ports"
        if rmdir "$_root/PORTS" 2>/dev/null; then
            log_message "Ports migration: merged $_root/PORTS into ports"
        else
            log_message "Ports migration: merged $_root/PORTS into ports but could not remove the old folder"
        fi
    fi
    # The mount point the old bind used, left behind empty.
    rmdir "$_root/ports/ports" 2>/dev/null
    return 0
}

migrate_ports_dir() {
    log_message "Ports migration: starting"
    normalize_ports_dir /mnt/SDCARD/Roms
    # The Flip's second card carries ROMs too (stock mounts it at /media/sdcard1).
    [ -d /media/sdcard1/Roms ] && normalize_ports_dir /media/sdcard1/Roms

    # Persisted absolute paths that would otherwise go stale: recents and the
    # last-played state. Entries only ever hold spruce-card paths.
    for _f in /mnt/SDCARD/Saves/pyui-recents.json /mnt/SDCARD/Saves/pyui-state.json; do
        [ -f "$_f" ] && sed -i 's|/Roms/PORTS/|/Roms/ports/|g' "$_f"
    done

    # A30 ports are hand-made scripts that hardcoded /mnt/SDCARD/Roms/PORTS/
    # from the days when spruce bound A30PORTS over that name. Point them at
    # their real folder so no bind is needed any more.
    if [ -d /mnt/SDCARD/Roms/A30PORTS ]; then
        for _s in /mnt/SDCARD/Roms/A30PORTS/*.sh; do
            [ -f "$_s" ] && sed -i 's|/mnt/SDCARD/Roms/PORTS/|/mnt/SDCARD/Roms/A30PORTS/|g' "$_s"
        done
    fi

    # PortMaster's config.py is re-patched by launch.sh at every PortMaster
    # start, but a port launched from the game list before then reads the
    # copy already on the card.
    _cfg=/mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py
    [ -f "$_cfg" ] && sed -i 's|/mnt/SDCARD/Roms/PORTS\([^0-9A-Za-z_]\)|/mnt/SDCARD/Roms/ports\1|g' "$_cfg"

    rm -f "$PORTS_MIGRATION_FLAG"
    log_message "Ports migration: done"
}
