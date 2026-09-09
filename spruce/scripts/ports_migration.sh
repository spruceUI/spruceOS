#!/bin/sh
#
# Roms/PORTS -> Roms/ports, once, on the first boot after an install or update.
# Ports look in $directory/ports/<game>; a lowercase folder needs no bind.
# The flag ships in every release/OTA; runtime.sh runs this when it is present.
# Decides by the folder's STORED name (-d matches either case on some mounts).

PORTS_MIGRATION_FLAG=/mnt/SDCARD/spruce/flags/ports_PORTS_migration

ports_dir_names() {
    ls -1 "$1" 2>/dev/null | grep -x 'PORTS\|ports'
}

# Make $1/ports the one and only ports folder under the Roms root $1.
normalize_ports_dir() {
    _root="$1"
    [ -d "$_root" ] || return 0
    # A power cut between the two mv's below leaves the games here.
    if [ -d "$_root/.ports.migrating" ]; then
        if ls -1 "$_root" | grep -qx ports; then
            merge_dir "$_root/.ports.migrating" "$_root/ports"
            rmdir "$_root/.ports.migrating" 2>/dev/null
        else
            mv "$_root/.ports.migrating" "$_root/ports"
        fi
        log_message "Ports migration: recovered an interrupted rename under $_root"
    fi
    _names="$(ports_dir_names "$_root")"
    _has_upper=0; _has_lower=0
    echo "$_names" | grep -qx PORTS && _has_upper=1
    echo "$_names" | grep -qx ports && _has_lower=1

    if [ "$_has_upper" = 0 ]; then
        [ "$_has_lower" = 0 ] && mkdir -p "$_root/ports"
        log_message "Ports migration: $_root/ports already in place" -v
    elif [ "$_has_lower" = 0 ]; then
        # Case-only mv is refused on case-insensitive mounts; go via a temp name.
        if mv "$_root/PORTS" "$_root/.ports.migrating" && mv "$_root/.ports.migrating" "$_root/ports"; then
            log_message "Ports migration: renamed $_root/PORTS to ports"
        else
            log_message "Ports migration: FAILED to rename $_root/PORTS"
            return 1
        fi
    else
        # Both exist (case-sensitive mount): fold PORTS into ports by rename.
        merge_dir "$_root/PORTS" "$_root/ports"
        if rmdir "$_root/PORTS" 2>/dev/null; then
            log_message "Ports migration: merged $_root/PORTS into ports"
        else
            log_message "Ports migration: merged $_root/PORTS into ports but could not remove the old folder"
        fi
    fi
    rmdir "$_root/ports/ports" 2>/dev/null
    return 0
}

migrate_ports_dir() {
    log_message "Ports migration: starting"
    if ! normalize_ports_dir /mnt/SDCARD/Roms; then
        log_message "Ports migration: leaving the flag so the next boot retries"
        return 1
    fi
    [ -d /media/sdcard1/Roms ] && normalize_ports_dir /media/sdcard1/Roms

    for _f in /mnt/SDCARD/Saves/pyui-recents.json /mnt/SDCARD/Saves/pyui-state.json /mnt/SDCARD/Saves/spruce/gtt.json; do
        [ -f "$_f" ] && sed -i 's|/Roms/PORTS/|/Roms/ports/|g' "$_f"
    done

    # A30 scripts hardcoded Roms/PORTS (the old bind); point them at A30PORTS.
    if [ -d /mnt/SDCARD/Roms/A30PORTS ]; then
        for _s in /mnt/SDCARD/Roms/A30PORTS/*.sh; do
            [ -f "$_s" ] && sed -i 's|/mnt/SDCARD/Roms/PORTS/|/mnt/SDCARD/Roms/A30PORTS/|g' "$_s"
        done
    fi

    _cfg=/mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py
    [ -f "$_cfg" ] && sed -i 's|/mnt/SDCARD/Roms/PORTS\([^0-9A-Za-z_]\)|/mnt/SDCARD/Roms/ports\1|g' "$_cfg"

    rm -f "$PORTS_MIGRATION_FLAG"
    log_message "Ports migration: done"
}
