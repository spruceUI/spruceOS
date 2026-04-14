#!/bin/sh

# Fix A30 RetroArch config after restore
# - Set input_driver to sdl2 (old value "sdl" broke input on A30)
# - Set video_rotation to 1 (A30 portrait panel needs rotation for landscape)
# - Set input_menu_toggle_btn to nul so the Guide button path works
#   (old value "9" broke standalone menu button toggle)
# - Add joypad _btn fallback values for hotkeys
#   (old configs only had keyboard bindings, no btn fallbacks)
#
# Fix MiyooMini RetroArch config for RetroAchievements
# - Add full cheevos settings block (old config only had cheevos_hardcore_mode_enable)
# - Set fps_show to false (OSD msg queue conflict blocks cheevos notifications)

TARGET_VERSION="4.1.1"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

# --- A30 RetroArch config fixes ---

RA_A30_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-A30.cfg"

if [ -f "$RA_A30_CFG" ]; then
    log_message "Patching A30 RetroArch config"

    # Fix input driver: must be sdl2 for A30
    sed 's|^input_driver = "sdl"|input_driver = "sdl2"|' \
        "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"

    # Fix video rotation: A30 portrait panel requires rotation 1 for landscape
    sed 's|^video_rotation = "0"|video_rotation = "1"|' \
        "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"

    # Fix menu toggle btn: must be nul for Guide button autoconfig path
    sed 's|^input_menu_toggle_btn = .*|input_menu_toggle_btn = "nul"|' \
        "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"

    # Add joypad btn fallbacks for hotkeys (only replace nul values)
    for pair in \
        "input_enable_hotkey_btn:6" \
        "input_exit_emulator_btn:0" \
        "input_fps_toggle_btn:2" \
        "input_load_state_btn:4" \
        "input_save_state_btn:5" \
        "input_screenshot_btn:1"
    do
        key="${pair%%:*}"
        val="${pair##*:}"
        sed "s|^${key} = \"nul\"|${key} = \"${val}\"|" \
            "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"
    done
else
    log_message "No retroarch-A30.cfg found, skipping A30 input fix"
fi

# --- MiyooMini RetroArch config fixes ---

RA_MINI_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-MiyooMini.cfg"

if [ -f "$RA_MINI_CFG" ]; then
    log_message "Patching MiyooMini RetroArch config"

    # Disable FPS display (conflicts with cheevos OSD notifications)
    sed 's|^fps_show = "true"|fps_show = "false"|' \
        "$RA_MINI_CFG" > "$RA_MINI_CFG.tmp" && mv "$RA_MINI_CFG.tmp" "$RA_MINI_CFG"

    # Add cheevos settings if missing (old config only had cheevos_hardcore_mode_enable)
    if ! grep -q '^cheevos_enable' "$RA_MINI_CFG"; then
        sed '/^cheevos_hardcore_mode_enable/i\
cheevos_appearance_anchor = "0"\
cheevos_appearance_padding_auto = "true"\
cheevos_appearance_padding_h = "0.000000"\
cheevos_appearance_padding_v = "0.000000"\
cheevos_auto_screenshot = "false"\
cheevos_badges_enable = "false"\
cheevos_challenge_indicators = "true"\
cheevos_custom_host = ""\
cheevos_enable = "false"' \
            "$RA_MINI_CFG" > "$RA_MINI_CFG.tmp" && mv "$RA_MINI_CFG.tmp" "$RA_MINI_CFG"

        sed '/^cheevos_hardcore_mode_enable/a\
cheevos_leaderboards_enable = ""\
cheevos_password = ""\
cheevos_richpresence_enable = "true"\
cheevos_start_active = "false"\
cheevos_test_unofficial = "false"\
cheevos_token = ""\
cheevos_unlock_sound_enable = "false"\
cheevos_username = ""\
cheevos_verbose_enable = "true"\
cheevos_visibility_account = "true"\
cheevos_visibility_lboard_cancel = "true"\
cheevos_visibility_lboard_start = "true"\
cheevos_visibility_lboard_submit = "true"\
cheevos_visibility_lboard_trackers = "true"\
cheevos_visibility_mastery = "true"\
cheevos_visibility_progress_tracker = "true"\
cheevos_visibility_summary = "1"\
cheevos_visibility_unlock = "true"' \
            "$RA_MINI_CFG" > "$RA_MINI_CFG.tmp" && mv "$RA_MINI_CFG.tmp" "$RA_MINI_CFG"

        log_message "Added RetroAchievements settings to MiyooMini config"
    else
        log_message "RetroAchievements settings already present, skipping"
    fi
else
    log_message "No retroarch-MiyooMini.cfg found, skipping MiyooMini fix"
fi

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
