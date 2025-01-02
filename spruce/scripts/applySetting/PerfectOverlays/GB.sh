#!/bin/sh
. /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/configEditHelpers.sh

# File paths
GB_GAMBATTE_CFG_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/Gambatte/GB.cfg
GB_GAMBATTE_GLSLP_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/Gambatte/GB.glslp
GB_GAMBATTE_GB_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/Gambatte/GB.opt

GB_MGBA_CFG_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GB.cfg
GB_MGBA_GLSLP_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GB.glslp
GB_MGBA_GB_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GB.opt


apply_overlay() {
    # Define configurations
    GB_CFG="input_overlay = \"./.retroarch/overlay/Perfect/Perfect_DMG-EX_533/DMG/Perfect_DMG-EX_533_mugwomp93.cfg\"
input_overlay_enable = \"true\"
input_overlay_opacity = \"1.000000\"
input_player1_analog_dpad_mode = \"0\"
video_crop_overscan = \"false\""

    GB_GLSP="shaders = \"1\"
shader0 = \"../../shaders/shaders/sharp-bilinear-simple.glsl\"
filter_linear0 = \"true\"
wrap_mode0 = \"clamp_to_border\"
mipmap_input0 = \"false\"
alias0 = \"\"
float_framebuffer0 = \"false\"
srgb_framebuffer0 = \"false\""

    GB_GAMBATTE_OPT="gambatte_gb_colorization = \"custom\"
gambatte_gb_internal_palette = \"Multicolor\"
gambatte_gb_palette_essentials = \"765 Production Ver.\"
gambatte_gb_palette_extras = \"GB New\"
gambatte_gb_palette_hardware = \"GB Kiosk\"
gambatte_gb_palette_multicolor = \"Special 3\"
gambatte_gb_palette_nintendo_official = \"GB - DMG\"
gambatte_gb_palette_others = \"Under Construction\"
gambatte_gb_palette_Single_Color = \"Super Saiyan Blue\"
gambatte_gb_palette_subtle = \"Silver Shiro\""

    GB_MGBA_OPT="mgba_gb_colorization = \"custom\"
mgba_gb_internal_palette = \"Multicolor\"
mgba_gb_palette_essentials = \"765 Production Ver.\"
mgba_gb_palette_extras = \"GB New\"
mgba_gb_palette_hardware = \"GB Kiosk\"
mgba_gb_palette_multicolor = \"Special 3\"
mgba_gb_palette_nintendo_official = \"GB - DMG\"
mgba_gb_palette_others = \"Under Construction\"
mgba_gb_palette_Single_Color = \"Super Saiyan Blue\"
mgba_gb_palette_subtle = \"Silver Shiro\""

    # Apply configurations
    update_config_file "$GB_GAMBATTE_CFG_FILE" "$GB_CFG"
    update_config_file "$GB_GAMBATTE_GLSLP_FILE" "$GB_GLSP"
    update_config_file "$GB_GAMBATTE_GB_FILE" "$GB_GAMBATTE_OPT"
    update_config_file "$GB_MGBA_CFG_FILE" "$GB_CFG"
    update_config_file "$GB_MGBA_GLSLP_FILE" "$GB_GLSP"
    update_config_file "$GB_MGBA_GB_FILE" "$GB_MGBA_OPT"
}

remove_overlay() {
    # Extract keys from the configuration data
    GB_CFG_KEYS="input_overlay
input_overlay_enable
input_overlay_opacity
input_player1_analog_dpad_mode
video_crop_overscan"

    GB_GLSP_KEYS="shaders
shader0
filter_linear0
wrap_mode0
mipmap_input0
alias0
float_framebuffer0
srgb_framebuffer0"

    # Define reset values for .opt files
    GB_GAMBATTE_OPT_RESET="gambatte_gb_colorization = \"internal\"
gambatte_gb_internal_palette = \"Essentials\"
gambatte_gb_palette_essentials = \"GB-DMG\"
gambatte_gb_palette_extras = \"Special 2\"
gambatte_gb_palette_hardware = \"GB Old\"
gambatte_gb_palette_nintendo_official = \"GB - Pocket\"
gambatte_gb_palette_others = \"Game Boy Pocket\"
gambatte_gb_palette_Single_Color = \"Mutant\"
gambatte_gb_palette_subtle = \"Grand Ivory\""

    GB_MGBA_OPT_RESET="mgba_gb_colorization = \"internal\"
mgba_gb_internal_palette = \"Essentials\"
mgba_gb_palette_essentials = \"GB-DMG\"
mgba_gb_palette_extras = \"Special 2\"
mgba_gb_palette_hardware = \"GB Old\"
mgba_gb_palette_nintendo_official = \"GB - Pocket\"
mgba_gb_palette_others = \"Game Boy Pocket\"
mgba_gb_palette_Single_Color = \"Mutant\"
mgba_gb_palette_subtle = \"Grand Ivory\""

    # Remove cfg and glslp configurations
    remove_config_entries "$GB_GAMBATTE_CFG_FILE" "$GB_CFG_KEYS"
    remove_config_entries "$GB_GAMBATTE_GLSLP_FILE" "$GB_GLSP_KEYS"
    remove_config_entries "$GB_MGBA_CFG_FILE" "$GB_CFG_KEYS"
    remove_config_entries "$GB_MGBA_GLSLP_FILE" "$GB_GLSP_KEYS"

    # Update opt files with reset values
    update_config_file "$GB_GAMBATTE_GB_FILE" "$GB_GAMBATTE_OPT_RESET"
    update_config_file "$GB_MGBA_GB_FILE" "$GB_MGBA_OPT_RESET"
}

# Check for command line argument
case "${1:-apply}" in
    "remove")
        remove_overlay
        ;;
    *)
        apply_overlay
        ;;
esac
