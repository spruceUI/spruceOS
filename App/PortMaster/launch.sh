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
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py
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
cp /mnt/SDCARD/App/PortMaster/config.py /mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py

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

cp "/mnt/SDCARD/App/PortMaster/.portmaster/device_info_Miyoo_Miyoo Flip.txt" "/mnt/SDCARD/Saves/flip/home/device_info_Miyoo_Miyoo Flip.txt"

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
