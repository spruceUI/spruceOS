#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

#ENV Variables

export HOME="/mnt/SDCARD/Saves/flip/home"

case "$PLATFORM" in
    Flip|SmartProS)
        export PYSDL2_DLL_PATH="/mnt/SDCARD/Persistent/portmaster/site-packages/sdl2dll/dll"
        export PATH="/mnt/SDCARD/spruce/flip/bin:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:$LD_LIBRARY_PATH"
        ;;
    Anbernic*)
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll-mali"
        export PATH="/mnt/SDCARD/spruce/flip/bin:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        # PortMaster's own splash is a love2d app - pmsplash.txt sources the
        # love_11.5 runtime and runs $LOVE_RUN on utils/pmsplash - so the GUI
        # needs the same libraries a love PORT does. BaseOS ships none of them,
        # and the runtime bundles only its own, so love died in the loader with
        # "libopenal.so.1: cannot open shared object file" and the splash never
        # drew. ports-lib64 is on PORTS_LD_LIBRARY_PATH for ports, but that is
        # built by run_port and the GUI never sees it. Appended, not prepended:
        # these are libraries BaseOS lacks outright, so they need to shadow
        # nothing.
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/mnt/SDCARD/spruce/h700/ports-lib64"
        # pugwash reads the pad through SDL_GameController and nothing else -
        # it handles CONTROLLERBUTTONDOWN and keyboard, never raw joystick
        # events. BaseOS ships no mapping for the built-in pad, so
        # SDL_IsGameController is false, no pad is opened, and every button
        # does nothing. AnbernicXXCommon.cfg already picked the right map for
        # this model; hand it to SDL and the menu responds.
        #
        # Label-named rather than positional: with no xbox fix on this
        # platform pugwash treats SDL's "a" as its confirm button, and the
        # label-named map puts "a" on the button actually marked A. That also
        # matches what a Miyoo Flip does, where the stock mapping is
        # positional but PlatformMiyoo flips A and B back.
        export_sdl_gamecontroller_map
        ;;
    Brick|SmartPro|BrickPro)
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        export PATH="/mnt/SDCARD/spruce/flip/bin:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:$LD_LIBRARY_PATH"
        ;;
    RGB30)
        # dArkMoss is Debian, so unlike every other spruce device the base
        # already carries what a port needs - SDL2 2.32 built for this Mali
        # blob, the GLES stack, and every library the Anbernic XX needed a
        # bundled ports-lib64 for. Point pysdl2 at the system SDL2 rather than
        # a spruce-bundled one for exactly that reason: dArkOS built it against
        # this GPU.
        #
        # pugwash still needs the bundled Python 3.10 on PATH; the base ships
        # 3.13 with no sdl2 module. Verified 3.10.16 runs on trixie's glibc.
        #
        # No mod_<CFW_NAME>.txt is staged. Upstream ships none for the ArkOS
        # family, which is what this base is, so ports are expected to run on
        # the defaults. Note CFW_NAME currently resolves to "Unknown" here
        # anyway: PortMaster identifies ArkOS by finding "arkos" inside the
        # plymouth title, and the dArkMoss rebrand ("darkmoss") does not
        # contain it. Cosmetic for now - nothing in harbourmaster reads
        # CFW_NAME - but it is why no shim can be keyed on the name yet.
        export PYSDL2_DLL_PATH="/usr/lib/aarch64-linux-gnu"
        export PATH="/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        # pugwash confirms on SDL's "a", which on this pad is positional and
        # therefore the button marked B. Hand SDL the label-named map so confirm
        # lands on the button marked A - same reason the Anbernic branch does it.
        export_sdl_gamecontroller_map
        # Ports and PortMaster.txt source mod_${CFW_NAME}.txt if it exists, and
        # nothing upstream ships one for the ArkOS family this base belongs to,
        # so pm_message dies with "command not found". Name it from the live
        # CFW_NAME rather than hardcoding: it reads "Unknown" today because
        # PortMaster identifies ArkOS by finding "arkos" in the plymouth title
        # and the dArkMoss rebrand does not contain it, but that can change
        # without this needing to.
        # device_info.txt is bash ([[ ]]) and this script is dash, so it has to
        # be sourced by bash or it aborts on syntax and yields an empty name.
        RGB30_CFW_NAME="$(bash -c '. /mnt/SDCARD/Persistent/portmaster/PortMaster/device_info.txt >/dev/null 2>&1; printf "%s" "$CFW_NAME"')"
        [ -n "$RGB30_CFW_NAME" ] || RGB30_CFW_NAME="Unknown"
        cp /mnt/SDCARD/App/PortMaster/mod_RGB30.txt \
           "/mnt/SDCARD/Persistent/portmaster/PortMaster/mod_${RGB30_CFW_NAME}.txt"
        ;;
    Pixel2)
        /usr/bin/start_portmaster.sh > /mnt/SDCARD/Saves/spruce/portmaster.log 2>&1
        /mnt/SDCARD/App/PortMaster/update_images.sh > /mnt/SDCARD/Saves/spruce/updated_images.log 2>&1
        rm /mnt/SDCARD/Roms/PORTS/gamelist.*
        exit 0
        ;;
esac

# Until PM-GUI is updated we need to override where spruce stores things
# Just replacing the entire file. This should go away soon
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/control.txt
# A self-update leaves pylibs.zip behind and pugwash unpacks it at startup -
# rmtree pylibs/ and exlibs/, extract, record the md5, delete the zip. Anything
# staged into pylibs/ before that is thrown away with the old tree, so the
# launch right after an update ran on upstream's config.py. Do the unpack here
# first, the same way pugwash does, so the config.py copy below lands on the
# tree pugwash will actually use. The bundled python is the one thing every
# platform has; unzip is not.
PM_DIR="/mnt/SDCARD/Persistent/portmaster/PortMaster"
if [ -f "$PM_DIR/pylibs.zip" ]; then
    log_message "PortMaster: unpacking pylibs.zip left by a self-update"
    rm -rf "$PM_DIR/pylibs" "$PM_DIR/exlibs"
    LD_LIBRARY_PATH="/mnt/SDCARD/Persistent/portmaster/lib:$LD_LIBRARY_PATH" \
        /mnt/SDCARD/Persistent/portmaster/bin/python3 -m zipfile -e "$PM_DIR/pylibs.zip" "$PM_DIR" \
        && md5sum "$PM_DIR/pylibs.zip" | cut -d' ' -f1 > "$PM_DIR/pylibs.zip.md5" \
        && rm -f "$PM_DIR/pylibs.zip"
fi
# Upstream's config.py has a spruce branch, but it targets a layout we do not
# use (/mnt/sdcard, Roms/.portmaster, Roms/PORTS64). Patch those four strings in
# place rather than dropping in our own copy of the file: harbourmaster does
# "from .config import *" and any symbol a newer upstream adds to config.py
# would be missing from a copy made against an older one (a self-updated
# 2026.07 tree with the 2025.03 copy staged in died on
# HM_ACCEPTABLE_NON_BASH_TOP_LEVEL_FILES). Whatever version the device has,
# it keeps its own config.py. Idempotent.
sed -i \
    -e 's|/mnt/sdcard/spruce|/mnt/SDCARD/spruce|' \
    -e 's|/mnt/sdcard/Persistent/portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/\.portmaster|/mnt/SDCARD/Persistent/portmaster|' \
    -e 's|/mnt/SDCARD/Roms/PORTS64|/mnt/SDCARD/Roms/PORTS|' \
    "$PM_DIR/pylibs/harbourmaster/config.py"
cp /mnt/SDCARD/App/PortMaster/PortMaster.txt /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
# ...and again under a name the updater does not own. bash reads a script
# incrementally by byte offset, so when pugwash's self-update replaces
# PortMaster.txt mid-run, the shell keeps reading at its saved offset into the
# NEW file and executes whatever bytes land there. That is where the
# "PortMaster.txt: line 262: unexpected EOF" in the logs comes from - our copy
# is 183 lines. It has only ever bitten at exit, but it is the shell running
# arbitrary spliced text, so run the private copy instead. PortMaster.txt is
# still staged above in case anything else invokes it by that name.
cp /mnt/SDCARD/App/PortMaster/PortMaster.txt /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/spruce_portmaster.sh
chmod +x /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/spruce_portmaster.sh
cp /mnt/SDCARD/App/PortMaster/control.txt /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/control.txt

rm /mnt/SDCARD/Saves/flip/home/.local/share/PortMaster/control.txt
cp /mnt/SDCARD/App/PortMaster/control.txt /mnt/SDCARD/Saves/flip/home/.local/share/PortMaster/control.txt

# Ports source "$controlfolder/mod_${CFW_NAME}.txt" if it exists, and that is
# the only hook that runs in the port's own shell after control.txt. On BaseOS
# nothing ships one, so gptokeyb ports had no working keyboard and every
# pm_message call died. Name it from the same field device_info.txt reads -
# NAME= in /etc/os-release, "Base OS" on today's builds - so this keeps working
# if BaseOS ever renames itself.
case "$PLATFORM" in
    Anbernic*)
        XX_CFW_NAME="$(grep -a '^NAME="' /etc/os-release 2>/dev/null | cut -d'"' -f2)"
        [ -n "$XX_CFW_NAME" ] || XX_CFW_NAME="Base OS"
        cp /mnt/SDCARD/App/PortMaster/mod_BaseOS.txt \
           "/mnt/SDCARD/Persistent/portmaster/PortMaster/mod_${XX_CFW_NAME}.txt"
        ;;
esac

#Launch port master
cd /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/

./spruce_portmaster.sh > /mnt/SDCARD/Saves/spruce/portmaster.log 2>&1

# pugwash asks for a restart after updating itself by dropping this flag. We
# deliberately do not restart in place - that would skip the staging above and
# leave the next pugwash on upstream's config.py, which costs the theme and
# sends ports to Roms/PORTS64. Exiting means the overrides get re-staged on the
# next launch instead. Just record it and clear it.
PM_REBOOT_FLAG="/mnt/SDCARD/Persistent/portmaster/PortMaster/.pugwash-reboot"
if [ -f "$PM_REBOOT_FLAG" ]; then
    log_message "PortMaster updated itself and asked to restart; exiting so the next launch re-applies spruce's config"
    rm -f "$PM_REBOOT_FLAG"
fi

# Fix images to be spruce compatible
/mnt/SDCARD/App/PortMaster/update_images.sh > /mnt/SDCARD/Saves/spruce/updated_images.log 2>&1

# Hide pm_message for miyoo as it creates some issues for us (jpg and broken ports)
FILE="/mnt/SDCARD/Persistent/portmaster/PortMaster/mod_Miyoo.txt"
grep -q '^pm_message()' "$FILE" 2>/dev/null || \
echo 'pm_message() { echo "$1" > "$CUR_TTY"; }' >> "$FILE"
