#!/bin/sh

# Fix PPSSPP Pause hotkey in controls INI files
# - A30: old binding "Pause = 10-106" (wrong keycode) → "Pause = 10-196:10-188" (Select+Triangle)
# - Flip: old binding "Pause = 1-111,10-109,10-104" (keyboard/raw codes) → "Pause = 10-196:10-188"
# - Brick/SmartPro/SmartProS/AnbernicRGCubeXX: Pause line was missing or wrong → fix it
# All devices now use the same unified Select+Triangle combo for Pause.
#
# Fix PPSSPP menu confirm button (ButtonPreference)
# - Old value 0 = Circle confirms (Japanese style, east button)
# - New value 1 = Cross confirms (Western style, south button)

TARGET_VERSION="4.1.2"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
NEW_PAUSE='Pause = 10-196:10-188'

patch_controls_file() {
    file="$1"
    [ -f "$file" ] || return 0

    if grep -q '^Pause = ' "$file"; then
        # Pause line exists — replace it if it doesn't already match
        current=$(grep '^Pause = ' "$file")
        if [ "$current" = "$NEW_PAUSE" ]; then
            log_message "$(basename "$file"): Pause already correct, skipping"
            return 0
        fi
        sed "s|^Pause = .*|$NEW_PAUSE|" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        log_message "$(basename "$file"): Updated Pause binding"
    else
        # Pause line missing — add it after Exit App (or at end of [ControlMapping] block)
        if grep -q '^Exit App = ' "$file"; then
            sed "/^Exit App = .*/a\\
$NEW_PAUSE" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            log_message "$(basename "$file"): Added Pause binding after Exit App"
        else
            echo "$NEW_PAUSE" >> "$file"
            log_message "$(basename "$file"): Appended Pause binding"
        fi
    fi
}


if [ "$PLATFORM" != "Pixel2" ]; then
    # Patch all per-platform controls files except the pixel2
    for ini in "$PSP_DIR"/controls-*.ini; do
        patch_controls_file "$ini"
    done

    # Patch the active controls.ini (restored from backup, may be stale)
    patch_controls_file "$PSP_DIR/controls.ini"
fi

# --- Fix PPSSPP menu confirm button ---

patch_button_preference() {
    file="$1"
    [ -f "$file" ] || return 0

    if grep -q '^ButtonPreference = 1' "$file"; then
        log_message "$(basename "$file"): ButtonPreference already correct, skipping"
        return 0
    fi

    if grep -q '^ButtonPreference = ' "$file"; then
        sed "s|^ButtonPreference = .*|ButtonPreference = 1|" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        log_message "$(basename "$file"): Updated ButtonPreference to 1"
    else
        echo "ButtonPreference = 1" >> "$file"
        log_message "$(basename "$file"): Added ButtonPreference = 1"
    fi
}

# Patch all per-platform ppsspp config files
for ini in "$PSP_DIR"/ppsspp-*.ini; do
    patch_button_preference "$ini"
done

# Patch the active ppsspp.ini (restored from backup, may be stale)
patch_button_preference "$PSP_DIR/ppsspp.ini"

# --- Disable verbose RetroArch logging ---
# log_verbosity was causing mGBA (and other chatty cores) to spam warnings
# every frame, stalling on I/O and degrading performance over time.

for cfg in \
    "/mnt/SDCARD/RetroArch/platform/retroarch-A30.cfg" \
    "/mnt/SDCARD/RetroArch/platform/retroarch-Brick.cfg" \
    "/mnt/SDCARD/RetroArch/platform/retroarch-MiyooMini.cfg" \
    "/mnt/SDCARD/RetroArch/platform/retroarch-SmartPro.cfg"
do
    if [ -f "$cfg" ]; then
        sed 's|^log_verbosity = "true"|log_verbosity = "false"|' \
            "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
        log_message "Disabled log_verbosity in $(basename "$cfg")"
    fi
done

# --- Fix RetroArch fullscreen and window max resolution per device ---
# Platform configs had 1920x1080 window_auto_max and 0x0 fullscreen
# regardless of actual panel size. Brick also had wrong viewport (960x720
# instead of 1024x768).

patch_ra_resolution() {
    cfg="$1" fs_w="$2" fs_h="$3" wa_w="$4" wa_h="$5"
    [ -f "$cfg" ] || return 0
    sed "s|^video_fullscreen_x = \"[^\"]*\"|video_fullscreen_x = \"$fs_w\"|" \
        "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    sed "s|^video_fullscreen_y = \"[^\"]*\"|video_fullscreen_y = \"$fs_h\"|" \
        "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    sed "s|^video_window_auto_width_max = \"[^\"]*\"|video_window_auto_width_max = \"$wa_w\"|" \
        "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    sed "s|^video_window_auto_height_max = \"[^\"]*\"|video_window_auto_height_max = \"$wa_h\"|" \
        "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    log_message "Fixed resolution in $(basename "$cfg") to ${fs_w}x${fs_h}"
}

RA_PLATFORM="/mnt/SDCARD/RetroArch/platform"
patch_ra_resolution "$RA_PLATFORM/retroarch-Brick.cfg"          1024 768 1024 768
patch_ra_resolution "$RA_PLATFORM/retroarch-SmartPro.cfg"       1280 720 1280 720
patch_ra_resolution "$RA_PLATFORM/retroarch-SmartProS.cfg"      1280 720 1280 720
patch_ra_resolution "$RA_PLATFORM/retroarch-A30.cfg"            640  480 640  480
patch_ra_resolution "$RA_PLATFORM/retroarch-Flip.cfg"           640  480 640  480
patch_ra_resolution "$RA_PLATFORM/retroarch-Pixel2.cfg"         640  480 640  480
patch_ra_resolution "$RA_PLATFORM/retroarch-AnbernicRG28XX.cfg" 640  480 640  480
patch_ra_resolution "$RA_PLATFORM/retroarch-AnbernicRG34XXSP.cfg" 720 480 720 480

# Fix Brick viewport (was 960x720 copied from SmartPro)
BRICK_CFG="$RA_PLATFORM/retroarch-Brick.cfg"
if [ -f "$BRICK_CFG" ]; then
    sed 's|^custom_viewport_width = "960"|custom_viewport_width = "1024"|' \
        "$BRICK_CFG" > "$BRICK_CFG.tmp" && mv "$BRICK_CFG.tmp" "$BRICK_CFG"
    sed 's|^custom_viewport_height = "720"|custom_viewport_height = "768"|' \
        "$BRICK_CFG" > "$BRICK_CFG.tmp" && mv "$BRICK_CFG.tmp" "$BRICK_CFG"
    sed 's|^custom_viewport_x = "160"|custom_viewport_x = "0"|' \
        "$BRICK_CFG" > "$BRICK_CFG.tmp" && mv "$BRICK_CFG.tmp" "$BRICK_CFG"
    log_message "Fixed Brick viewport to 1024x768"
fi

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
