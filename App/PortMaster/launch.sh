#!/bin/sh
# spruce's PortMaster app launcher.
#
# PortMaster identifies a firmware and runs that firmware's control.txt,
# PortMaster.txt and mod_<CFW>.txt. Until PortMaster ships a PortMaster/spruce/
# set of its own, spruce stages the three files from App/PortMaster/ into the
# bundle on every launch (a self-update puts upstream's back). Those three are
# small on purpose: each ends by sourcing a hook on the card under
# spruce/portmaster/, which is where everything device-specific lives.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export HOME="/mnt/SDCARD/Saves/flip/home"
PM_ROOT="/mnt/SDCARD/Persistent/portmaster"
PM_DIR="$PM_ROOT/PortMaster"
OURS="/mnt/SDCARD/App/PortMaster"

if [ "$PLATFORM" = "Pixel2" ]; then
    # The Pixel 2 runs PortMaster's own layout untouched.
    /usr/bin/start_portmaster.sh > /mnt/SDCARD/Saves/spruce/portmaster.log 2>&1
    "$OURS/update_images.sh" > /mnt/SDCARD/Saves/spruce/updated_images.log 2>&1
    rm -f /mnt/SDCARD/Roms/ports/gamelist.*
    exit 0
fi

# The same device environment PortMaster.txt applies before pugwash; applied
# here too so the pylibs unpack below runs under it. Safe to source twice.
. /mnt/SDCARD/spruce/portmaster/portmaster.txt

# A self-update leaves pylibs.zip for the next start to unpack. Do it here,
# with the bundled Python, so the config.py patch below lands on the new tree.
if [ -f "$PM_DIR/pylibs.zip" ]; then
    log_message "PortMaster: unpacking pylibs.zip left by a self-update"
    rm -rf "$PM_DIR/pylibs" "$PM_DIR/exlibs"
    LD_LIBRARY_PATH="$PM_ROOT/lib:$LD_LIBRARY_PATH" \
        "$PM_ROOT/bin/python3" -m zipfile -e "$PM_DIR/pylibs.zip" "$PM_DIR" \
        && md5sum "$PM_DIR/pylibs.zip" | cut -d' ' -f1 > "$PM_DIR/pylibs.zip.md5" \
        && rm -f "$PM_DIR/pylibs.zip"
fi

# harbourmaster's spruce branch in config.py still carries the paths from the
# 2025 upstream PR, which never matched a shipping spruce. Patch whatever
# pugwash version is on the card rather than shipping a copy of the file, so
# pylibs always stays self-consistent.
sed -i \
    -e 's|/mnt/sdcard/spruce|/mnt/SDCARD/spruce|' \
    -e 's|/mnt/sdcard/Persistent/portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/\.portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/PORTS64|/mnt/SDCARD/Roms/ports|' \
    -e 's|/mnt/SDCARD/Roms/PORTS\([^0-9A-Za-z_]\)|/mnt/SDCARD/Roms/ports\1|g' \
    "$PM_DIR/pylibs/harbourmaster/config.py"

if [ -f "$PM_DIR/spruce/control.txt" ]; then
    # PortMaster knows spruce: its PlatformSpruce installed these itself.
    LAUNCHER="$PM_DIR/PortMaster.sh"
else
    rm -f "$PM_DIR/miyoo/PortMaster.txt" "$PM_DIR/miyoo/control.txt"
    cp "$OURS/PortMaster.txt" "$PM_DIR/miyoo/PortMaster.txt"
    cp "$OURS/PortMaster.txt" "$PM_DIR/miyoo/spruce_portmaster.sh"
    chmod +x "$PM_DIR/miyoo/spruce_portmaster.sh"
    cp "$OURS/control.txt" "$PM_DIR/miyoo/control.txt"

    # Every port probes $XDG_DATA_HOME/PortMaster/control.txt first; under
    # spruce that is this path, so it must always be our control.txt.
    rm -f "$HOME/.local/share/PortMaster/control.txt"
    mkdir -p "$HOME/.local/share/PortMaster"
    cp "$OURS/control.txt" "$HOME/.local/share/PortMaster/control.txt"

    # Ports and PortMaster.txt source mod_${CFW_NAME}.txt, whatever
    # device_info.txt decides this firmware is called (Miyoo, TrimUI, Base OS,
    # Unknown on the RGB30...). Stage ours under that name so spruce's hook
    # runs on every device, and under its own name for when upstream learns it.
    CFW_NAME="$(bash -c ". \"$PM_DIR/device_info.txt\" >/dev/null 2>&1; printf '%s' \"\$CFW_NAME\"")"
    [ -n "$CFW_NAME" ] || CFW_NAME="Unknown"
    cp "$OURS/mod_spruce.txt" "$PM_DIR/mod_${CFW_NAME}.txt"
    cp "$OURS/mod_spruce.txt" "$PM_DIR/mod_spruce.txt"

    LAUNCHER="$PM_DIR/miyoo/spruce_portmaster.sh"
fi

cd "$(dirname "$LAUNCHER")" && "$LAUNCHER" > /mnt/SDCARD/Saves/spruce/portmaster.log 2>&1

# A self-update asks for a restart by dropping this flag. PortMaster.txt exits
# instead of restarting, so the next launch comes back through here and
# re-stages everything against the new pugwash.
PM_REBOOT_FLAG="$PM_DIR/.pugwash-reboot"
if [ -f "$PM_REBOOT_FLAG" ]; then
    log_message "PortMaster updated itself and asked to restart; exiting so the next launch re-applies spruce's config"
    rm -f "$PM_REBOOT_FLAG"
fi

"$OURS/update_images.sh" > /mnt/SDCARD/Saves/spruce/updated_images.log 2>&1
