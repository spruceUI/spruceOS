#!/bin/sh
#
# Anbernic RG XX line: carry the fleet pad layout onto cards that update.
#
# spruceRestore extracts the user's backup over the new payload before this
# runs, and that backup contains RetroArch/platform/retroarch-AnbernicRG_XX-
# universal.cfg and the whole PPSSPP config tree under Saves. So the two files
# the parity change edits never arrive on an existing card by themselves:
#
#   - The universal cfg's hotkey ACTION binds do not matter: ra_functions.sh's
#     apply_xx_hotkeys_from_autoconfig rewrites every one of them by name from
#     the autoconfig on each launch. The MODIFIER is the exception. Under the
#     "Custom" option the launcher only translates the udev literals spruce
#     itself wrote, and on cards updated from 4.3.6 the cfg holds either the
#     old shipped "6" (never translated under Custom, which is why the
#     modifier was X on the 64-bit build - SPR-MED-094) or the "9" the old
#     Select translation wrote. Both are spruce's doing, not the user's, so
#     they move to the new shipped default MENU (udev "8"), which the launcher
#     turns into 11 for sdl2 and leaves at 8 for linuxraw. Anything else is a
#     value the user chose in RetroArch and stays. A user whose spruce option
#     is Select or Start is re-bound by name on every launch regardless, so
#     the rewrite is harmless there too.
#
#     The option is read from the BACKUP copy of spruce-config.json: this runs
#     before restore_spruce_config merges the user's values into the new file,
#     so the live file still holds the shipped default at this point.
#
#   - PPSSPP keeps its per-platform controls in Saves/.config/ppsspp, seeded
#     once from Emu/PSP/default_configs. Only the CubeXX had shipped files;
#     the RG28XX, XX640480 and XX720480 files are copied in when absent so
#     those models stop launching PPSSPP on its built-in defaults. An existing
#     file is the user's and is left alone.
#
# Nothing else in the change needs carrying: the DraStic, mupen64plus and
# PCSX files live in Emu/ directories the updater replaces, and the PCSX and
# YabaSanshiro pad sections are regenerated at every launch.
#
# Idempotent: a second pass finds "8" and finds the ini files present. Never
# fails the restore.
#
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

case "$PLATFORM" in
    "Anbernic"*) ;;
    *)
        log_message "4.3.7: not an Anbernic XX device, nothing to do"
        exit 0
        ;;
esac

# --- RetroArch modifier -------------------------------------------------------
RA_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg"
CONFIG_BACKUP="/mnt/SDCARD/Saves/spruce/backups/spruce-config.json"
CONFIG_LIVE="/mnt/SDCARD/Saves/spruce/spruce-config.json"

if [ -f "$RA_CFG" ]; then
    option=""
    for cfg in "$CONFIG_BACKUP" "$CONFIG_LIVE"; do
        [ -f "$cfg" ] || continue
        option="$(jq -r '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected // empty' "$cfg" 2>/dev/null)"
        [ -n "$option" ] && break
    done
    current="$(sed -n 's/^input_enable_hotkey_btn = "\([^"]*\)".*/\1/p' "$RA_CFG" | head -n 1)"
    case "$option:$current" in
        Custom:6|Custom:9|:6|:9)
            if sed 's/^input_enable_hotkey_btn = .*/input_enable_hotkey_btn = "8"/' "$RA_CFG" > "$RA_CFG.tmp" \
               && [ -s "$RA_CFG.tmp" ]; then
                mv -f "$RA_CFG.tmp" "$RA_CFG"
                log_message "4.3.7: RetroArch modifier moved from spruce default $current to MENU (8)"
            else
                rm -f "$RA_CFG.tmp"
                log_message "4.3.7: could not rewrite $RA_CFG - the modifier stays at $current"
            fi
            ;;
        *)
            log_message "4.3.7: RetroArch modifier left as is (option '${option:-unset}', value '${current:-unset}')"
            ;;
    esac
else
    log_message "4.3.7: no universal RetroArch cfg on this card, skipping the modifier"
fi

# --- PPSSPP per-platform configs ---------------------------------------------
PSP_LIVE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
PSP_DEFAULTS="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM"

if [ -d "$PSP_LIVE" ]; then
    copied=0
    for plat in AnbernicRG28XX AnbernicXX640480 AnbernicXX720480; do
        for kind in controls ppsspp; do
            src="$PSP_DEFAULTS/$kind-$plat.ini"
            dst="$PSP_LIVE/$kind-$plat.ini"
            [ -f "$src" ] || continue
            [ -e "$dst" ] && continue
            cp -f "$src" "$dst" && copied=$((copied + 1))
        done
    done
    log_message "4.3.7: PPSSPP defaults copied for $copied missing per-platform file(s)"
else
    log_message "4.3.7: PPSSPP has never been set up on this card, nothing to seed"
fi

sync
exit 0
