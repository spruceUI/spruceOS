#!/bin/sh
#
# Anbernic RG XX line: one RetroArch cfg per platform, and the fleet pad layout
# carried onto cards that update.
#
# spruceRestore extracts the user's backup over the new payload before this
# runs. Two things in that backup need help:
#
#   - Until this release the four XX platforms launched RetroArch on one shared
#     file, RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg, and the
#     backup list carried it. The fleet precedent since the 2025-04 restructure
#     is one cfg per platform, picked by $PLATFORM at launch, so a card that
#     moves between models never launches on another model's saved state. The
#     payload now ships retroarch-<PLATFORM>.cfg (+ .bak) for all four models
#     and the launcher, reset task and backup list use those. A restored
#     universal cfg is the user's RetroArch state (config_save_on_exit writes
#     everything back into it), so it is COPIED over this platform's shipped
#     cfg rather than dropped - the user's settings carry over, the other three
#     platforms keep the shipped defaults, and "Reset RetroArch config" (the
#     .bak, never backed up) is the way back to the defaults. The rotation and
#     fullscreen size are set for this platform once during the copy: the
#     launcher no longer forces them on every launch, so a value RetroArch
#     saved on another model must not ride along. The universal pair is then
#     removed: RetroArch/ is never deleted by the updater, so nothing else
#     would.
#
#   - Until this release the launcher rewrote every hotkey at each launch, so
#     a carried-over cfg holds whatever numbering the last launch used: udev
#     literals (never launched), linuxraw (last run on the 32-bit build) or
#     sdl2. The platform cfgs now ship the fleet layout in the 64-bit build's
#     sdl2 numbering and nothing rewrites it at launch, so a cfg still in an
#     old numbering (both put exit-emulator on "1"; sdl2 has "4") gets the
#     shipped set once, with the modifier mapped to the same control. No user
#     hotkey choice can be lost here: the old launcher overwrote them all
#     every launch anyway.
#
#   - The MODIFIER under the "Custom" option: on cards updated from 4.3.6 the
#     cfg holds either the old shipped "6" (never translated under Custom,
#     which is why the modifier was X on the 64-bit build - SPR-MED-094) or
#     the "9" the old Select translation wrote. Both are spruce's doing, not
#     the user's, so they move to the shipped default MENU (sdl2 "11").
#     Anything else is a value the user chose in RetroArch and stays. A user
#     whose spruce option is Select or Start is re-bound by the launcher on
#     every launch regardless, so the rewrite is harmless there too.
#
#     The option is read from the BACKUP copy of spruce-config.json: this runs
#     before restore_spruce_config merges the user's values into the new file,
#     so the live file still holds the shipped default at this point.
#
#   - PPSSPP keeps its per-platform controls in Saves/.config/ppsspp, seeded
#     once from Emu/PSP/default_configs. Only the CubeXX had shipped files;
#     the RG28XX, XX640480, XX720480 and the three stickless / one-stick
#     platforms' files are copied in when absent so
#     those models stop launching PPSSPP on its built-in defaults. An existing
#     file is the user's and is left alone.
#
# Nothing else in the change needs carrying: the DraStic, mupen64plus and
# PCSX files live in Emu/ directories the updater replaces (the XX DraStic
# cfgs are in the backup list, and "Reset DraStic config" restores their
# .bak), and the PCSX and YabaSanshiro pad sections are regenerated at every
# launch.
#
# Idempotent: a second pass finds no universal cfg, no udev driver, exit-emulator
# on "4" and the modifier on "11", and finds the ini files present. Never fails
# the restore.
#
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

case "$PLATFORM" in
    "Anbernic"*) ;;
    *)
        log_message "4.3.7: not an Anbernic XX device, nothing to do"
        exit 0
        ;;
esac

RA_PLATFORM_DIR="/mnt/SDCARD/RetroArch/platform"
RA_CFG="$RA_PLATFORM_DIR/retroarch-$PLATFORM.cfg"
RA_UNIVERSAL="$RA_PLATFORM_DIR/retroarch-AnbernicRG_XX-universal.cfg"
CONFIG_BACKUP="/mnt/SDCARD/Saves/spruce/backups/spruce-config.json"
CONFIG_LIVE="/mnt/SDCARD/Saves/spruce/spruce-config.json"

# --- Universal cfg -> this platform's cfg -------------------------------------
if [ -f "$RA_UNIVERSAL" ]; then
    if [ "$PLATFORM" = "AnbernicRG28XX" ]; then
        rot="1"; vid_x="640"; vid_y="480"
    else
        rot="0"; vid_x="0"; vid_y="0"
    fi
    if sed \
        -e "s|^video_rotation = .*|video_rotation = \"$rot\"|" \
        -e "s|^video_fullscreen_x = .*|video_fullscreen_x = \"$vid_x\"|" \
        -e "s|^video_fullscreen_y = .*|video_fullscreen_y = \"$vid_y\"|" \
        "$RA_UNIVERSAL" > "$RA_CFG.tmp" && [ -s "$RA_CFG.tmp" ]; then
        mv -f "$RA_CFG.tmp" "$RA_CFG"
        rm -f "$RA_UNIVERSAL" "$RA_UNIVERSAL.bak"
        log_message "4.3.7: RetroArch settings carried from the universal cfg into ${RA_CFG##*/} (rotation $rot, fullscreen ${vid_x}x${vid_y}); universal pair removed"
    else
        rm -f "$RA_CFG.tmp"
        log_message "4.3.7: could not carry the universal cfg into ${RA_CFG##*/} - the shipped cfg stays, the universal cfg is left in place"
    fi
fi

# --- Drivers and pad binds the platform cfg must carry itself ----------------
# Under the old scheme the sdl2 drivers came from a --appendconfig overlay and
# the built-in pad's binds from a name-matched autoconfig, so a universal cfg
# carried over above holds udev drivers and no player binds: RetroArch never
# had those values to save. Overlay and autoconfig are gone (the cfg owns them
# now, Brick precedent), so a carried cfg would start with no pad at all.
# Splice the shipped values for exactly those keys from the platform's .bak,
# plus the fleet hotkey binds: the drivers were never the user's choice
# (spruce forced them every launch), the built-in pad's binds never lived in
# the cfg, and the old launcher rewrote every hotkey at every launch for
# whichever model last ran the card - so a carried cfg's triggers may be
# another layout's, and none of them is a user value. The modifier stays: under
# Custom it can be the user's (the block below handles spruce's own literals).
# Everything else stays the user's. udev is the tell: no XX cfg ships it any
# more and BaseOS has no udevd, so a cfg holding it cannot see the pad. Also
# repairs a cfg an earlier run of this script carried.
if [ -f "$RA_CFG" ] && [ -f "$RA_CFG.bak" ] && grep -q '^input_joypad_driver = "udev"$' "$RA_CFG"; then
    if awk '
        NR == FNR {
            if ($0 ~ /^(input_driver|input_joypad_driver|video_context_driver|input_player1_[a-z0-9_]+|input_(exit_emulator|screenshot|menu_toggle|fps_toggle|load_state|save_state|toggle_slowmotion|toggle_fast_forward|shader_toggle|state_slot_decrease|state_slot_increase)_(btn|axis)) = /) {
                split($0, kv, " = "); want[kv[1]] = $0
            }
            next
        }
        {
            split($0, kv, " = ")
            if (kv[1] in want) { print want[kv[1]]; seen[kv[1]] = 1 } else print
        }
        END { for (k in want) if (!(k in seen)) print want[k] }
    ' "$RA_CFG.bak" "$RA_CFG" > "$RA_CFG.tmp" && [ -s "$RA_CFG.tmp" ]; then
        mv -f "$RA_CFG.tmp" "$RA_CFG"
        log_message "4.3.7: sdl2 drivers, the built-in pad's binds and the fleet hotkeys spliced into ${RA_CFG##*/} from the shipped cfg (the carried cfg held udev and no binds)"
    else
        rm -f "$RA_CFG.tmp"
        log_message "4.3.7: could not splice drivers and binds into $RA_CFG - RetroArch may start with no pad; run Reset RetroArch config"
    fi
fi

# --- Hotkeys in the 64-bit build's numbering, once ----------------------------
if [ -f "$RA_CFG" ] && grep -q '^input_exit_emulator_btn = "1"$' "$RA_CFG"; then
    case "$XX_PAD_LAYOUT" in
        nostick) l2_btn="12"; r2_btn="13" ;;
        *)       l2_btn="13"; r2_btn="14" ;;
    esac
    old_modifier="$(sed -n 's/^input_enable_hotkey_btn = "\([^"]*\)".*/\1/p' "$RA_CFG" | head -n 1)"
    case "$old_modifier" in
        6) new_modifier="9" ;;
        7) new_modifier="10" ;;
        *) new_modifier="11" ;;
    esac
    if sed \
        -e "s/^input_enable_hotkey_btn = .*/input_enable_hotkey_btn = \"$new_modifier\"/" \
        -e 's/^input_exit_emulator_btn = .*/input_exit_emulator_btn = "4"/' \
        -e 's/^input_screenshot_btn = .*/input_screenshot_btn = "3"/' \
        -e 's/^input_menu_toggle_btn = .*/input_menu_toggle_btn = "6"/' \
        -e 's/^input_fps_toggle_btn = .*/input_fps_toggle_btn = "5"/' \
        -e 's/^input_load_state_btn = .*/input_load_state_btn = "7"/' \
        -e 's/^input_save_state_btn = .*/input_save_state_btn = "8"/' \
        -e "s/^input_toggle_slowmotion_btn = .*/input_toggle_slowmotion_btn = \"$l2_btn\"/" \
        -e "s/^input_toggle_fast_forward_btn = .*/input_toggle_fast_forward_btn = \"$r2_btn\"/" \
        -e 's/^input_shader_toggle_btn = .*/input_shader_toggle_btn = "h0up"/' \
        -e 's/^input_state_slot_decrease_btn = .*/input_state_slot_decrease_btn = "h0left"/' \
        -e 's/^input_state_slot_increase_btn = .*/input_state_slot_increase_btn = "h0right"/' \
        -e 's/^input_\(exit_emulator\|screenshot\|menu_toggle\|fps_toggle\|load_state\|save_state\|toggle_slowmotion\|toggle_fast_forward\|shader_toggle\|state_slot_decrease\|state_slot_increase\)_axis = .*/input_\1_axis = "nul"/' \
        "$RA_CFG" > "$RA_CFG.tmp" && [ -s "$RA_CFG.tmp" ]; then
        mv -f "$RA_CFG.tmp" "$RA_CFG"
        log_message "4.3.7: RetroArch hotkeys moved from the old launcher numbering to the shipped sdl2 set (modifier $old_modifier -> $new_modifier)"
    else
        rm -f "$RA_CFG.tmp"
        log_message "4.3.7: could not rewrite the hotkeys in $RA_CFG - they stay in the old numbering"
    fi
fi

# --- RetroArch modifier -------------------------------------------------------
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
            if sed 's/^input_enable_hotkey_btn = .*/input_enable_hotkey_btn = "11"/' "$RA_CFG" > "$RA_CFG.tmp" \
               && [ -s "$RA_CFG.tmp" ]; then
                mv -f "$RA_CFG.tmp" "$RA_CFG"
                log_message "4.3.7: RetroArch modifier moved from spruce default $current to MENU (11)"
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
    log_message "4.3.7: no ${RA_CFG##*/} on this card, skipping the modifier"
fi

# --- PPSSPP per-platform configs ---------------------------------------------
PSP_LIVE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
PSP_DEFAULTS="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM"

if [ -d "$PSP_LIVE" ]; then
    copied=0
    for plat in AnbernicRG28XX AnbernicXX640480 AnbernicXX640480NoStick AnbernicXX640480OneStick AnbernicXX720480 AnbernicXX720480NoStick; do
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
