#!/bin/sh
# PortMaster app launcher. Stages spruce's three PortMaster files unless the
# bundle itself knows spruce (upstream merged).

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

. /mnt/SDCARD/spruce/portmaster/portmaster.txt

# Unpack a self-update's pylibs.zip before patching config.py below.
if [ -f "$PM_DIR/pylibs.zip" ]; then
    log_message "PortMaster: unpacking pylibs.zip left by a self-update"
    rm -rf "$PM_DIR/pylibs" "$PM_DIR/exlibs"
    LD_LIBRARY_PATH="$PM_ROOT/lib:$LD_LIBRARY_PATH" \
        "$PM_ROOT/bin/python3" -m zipfile -e "$PM_DIR/pylibs.zip" "$PM_DIR" \
        && md5sum "$PM_DIR/pylibs.zip" | cut -d' ' -f1 > "$PM_DIR/pylibs.zip.md5" \
        && rm -f "$PM_DIR/pylibs.zip"
fi

# config.py's spruce paths (from upstream #237) never matched spruce; patch in place.
sed -i \
    -e 's|/mnt/sdcard/spruce|/mnt/SDCARD/spruce|' \
    -e 's|/mnt/sdcard/Persistent/portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/\.portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/PORTS64|/mnt/SDCARD/Roms/ports|' \
    -e 's|/mnt/SDCARD/Roms/PORTS\([^0-9A-Za-z_]\)|/mnt/SDCARD/Roms/ports\1|g' \
    "$PM_DIR/pylibs/harbourmaster/config.py"

# A self-update extracts over the bundle without deleting spruce/, so test the
# files it does replace.
if grep -q 'CFW_NAME="spruce"' "$PM_DIR/device_info.txt" 2>/dev/null \
    && grep -q "PlatformSpruce" "$PM_DIR/pylibs/harbourmaster/platform.py" 2>/dev/null; then
    LAUNCHER="$PM_DIR/PortMaster.sh"
    # The update that brought PlatformSpruce ran the old platform's post-install.
    cp "$PM_DIR/spruce/PortMaster.txt" "$LAUNCHER" && chmod +x "$LAUNCHER"
else
    rm -f "$PM_DIR/miyoo/PortMaster.txt" "$PM_DIR/miyoo/control.txt"
    cp "$OURS/PortMaster.txt" "$PM_DIR/miyoo/PortMaster.txt"
    cp "$OURS/PortMaster.txt" "$PM_DIR/miyoo/spruce_portmaster.sh"
    chmod +x "$PM_DIR/miyoo/spruce_portmaster.sh"
    cp "$OURS/control.txt" "$PM_DIR/miyoo/control.txt"

    # Ports probe $XDG_DATA_HOME/PortMaster/control.txt first.
    rm -f "$HOME/.local/share/PortMaster/control.txt"
    mkdir -p "$HOME/.local/share/PortMaster"
    cp "$OURS/control.txt" "$HOME/.local/share/PortMaster/control.txt"

    # Ports source mod_${CFW_NAME}.txt, whatever device_info.txt calls this firmware.
    CFW_NAME="$(bash -c ". \"$PM_DIR/device_info.txt\" >/dev/null 2>&1; printf '%s' \"\$CFW_NAME\"")"
    [ -n "$CFW_NAME" ] || CFW_NAME="Unknown"
    cp "$OURS/mod_spruce.txt" "$PM_DIR/mod_${CFW_NAME}.txt"
    cp "$OURS/mod_spruce.txt" "$PM_DIR/mod_spruce.txt"

    LAUNCHER="$PM_DIR/miyoo/spruce_portmaster.sh"
fi

cd "$(dirname "$LAUNCHER")" && "$LAUNCHER" > /mnt/SDCARD/Saves/spruce/portmaster.log 2>&1

PM_REBOOT_FLAG="$PM_DIR/.pugwash-reboot"
if [ -f "$PM_REBOOT_FLAG" ]; then
    log_message "PortMaster updated itself and asked to restart; exiting so the next launch re-applies spruce's config"
    rm -f "$PM_REBOOT_FLAG"
fi

"$OURS/update_images.sh" > /mnt/SDCARD/Saves/spruce/updated_images.log 2>&1
