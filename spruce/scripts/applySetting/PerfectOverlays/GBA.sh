#!/bin/sh
. /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/configEditHelpers.sh

# File paths
GBA_GPSP_CFG_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/gpSP/GBA.cfg
GBA_GPSP_GLSLP_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/gpSP/GBA.glslp
GBA_GPSP_GB_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/gpSP/GBA.opt

GBA_MGBA_CFG_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GBA.cfg
GBA_MGBA_GLSLP_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GBA.glslp
GBA_MGBA_GB_FILE=/mnt/SDCARD/RetroArch/.retroarch/config/mGBA/GBA.opt


apply_overlay() {
    # Define configurations
    GBA_CFG="aspect_ratio_index = \"23\"
custom_viewport_height = \"427\"
input_overlay = \"./.retroarch/overlay/Perfect/Perfect_GBA/Bright_Version/Perfect_GBA_bright_1playerinsertcoin_adapted.cfg\"
input_overlay_enable = \"true\"
input_overlay_opacity = \"1.000000\"
input_player1_analog_dpad_mode = \"0\"
video_crop_overscan = \"false\""

    GBA_GLSP="shaders = \"1\"
shader0 = \"../../shaders/sharpshimmerless/shaders/sharp-shimmerless.glsl\"
filter_linear0 = \"true\"
wrap_mode0 = \"clamp_to_border\"
mipmap_input0 = \"false\"
alias0 = \"\"
float_framebuffer0 = \"false\"
srgb_framebuffer0 = \"false\""

    GBA_GPSP_OPT="gpsp_allow_opposing_directions = \"no\"
gpsp_audio_low_pass_filter = \"disabled\"
gpsp_audio_low_pass_range = \"60\"
gpsp_bios = \"auto\"
gpsp_boot_mode = \"game\"
gpsp_color_correction = \"disabled\"
gpsp_drc = \"enabled\"
gpsp_force_gbp = \"OFF\"
gpsp_frame_mixing = \"disabled\"
gpsp_frameskip = \"disabled\"
gpsp_frameskip_interval = \"0\"
gpsp_frameskip_threshold = \"33\"
gpsp_gb_colors = \"SGB 1-A\"
gpsp_gb_colors_preset = \"0\"
gpsp_gb_model = \"Autodetect\"
gpsp_idle_optimization = \"Remove Known\"
gpsp_interframe_blending = \"mix\"
gpsp_save_method = \"gpSP\"
gpsp_sgb_borders = \"ON\"
gpsp_skip_bios = \"ON\"
gpsp_solar_sensor_level = \"0\"
gpsp_sprlim = \"disabled\"
gpsp_turbo_period = \"4\"
gpsp_use_bios = \"OFF\""

    GBA_MGBA_OPT="mgba_allow_opposing_directions = \"no\"
mgba_audio_low_pass_filter = \"disabled\"
mgba_audio_low_pass_range = \"60\"
mgba_color_correction = \"OFF\"
mgba_force_gbp = \"OFF\"
mgba_frameskip = \"disabled\"
mgba_frameskip_interval = \"0\"
mgba_frameskip_threshold = \"33\"
mgba_gb_colors = \"SGB 1-A\"
mgba_gb_colors_preset = \"0\"
mgba_gb_model = \"Autodetect\"
mgba_idle_optimization = \"Remove Known\"
mgba_interframe_blending = \"mix\"
mgba_sgb_borders = \"ON\"
mgba_skip_bios = \"ON\"
mgba_solar_sensor_level = \"0\"
mgba_use_bios = \"OFF\""

    # Apply configurations
    update_config_file "$GBA_GPSP_CFG_FILE" "$GBA_CFG"
    update_config_file "$GBA_GPSP_GLSLP_FILE" "$GBA_GLSP"
    update_config_file "$GBA_GPSP_GB_FILE" "$GBA_GPSP_OPT"
    update_config_file "$GBA_MGBA_CFG_FILE" "$GBA_CFG"
    update_config_file "$GBA_MGBA_GLSLP_FILE" "$GBA_GLSP"
    update_config_file "$GBA_MGBA_GB_FILE" "$GBA_MGBA_OPT"
}

remove_overlay() {
    # Extract keys from the configuration data
    GBA_CFG_KEYS="aspect_ratio_index
custom_viewport_height
input_overlay
input_overlay_enable
input_overlay_opacity
input_player1_analog_dpad_mode
video_crop_overscan"

    GBA_GLSP_KEYS="shaders
shader0
filter_linear0
wrap_mode0
mipmap_input0
alias0
float_framebuffer0
srgb_framebuffer0"

    GBA_GPSP_OPT_KEYS="gpsp_allow_opposing_directions
gpsp_audio_low_pass_filter
gpsp_audio_low_pass_range
gpsp_bios
gpsp_boot_mode
gpsp_color_correction
gpsp_drc
gpsp_force_gbp
gpsp_frame_mixing
gpsp_frameskip
gpsp_frameskip_interval
gpsp_frameskip_threshold
gpsp_gb_colors
gpsp_gb_colors_preset
gpsp_gb_model
gpsp_idle_optimization
gpsp_interframe_blending
gpsp_save_method
gpsp_sgb_borders
gpsp_skip_bios
gpsp_solar_sensor_level
gpsp_sprlim
gpsp_turbo_period
gpsp_use_bios"

    GBA_MGBA_OPT_KEYS="mgba_allow_opposing_directions
mgba_audio_low_pass_filter
mgba_audio_low_pass_range
mgba_color_correction
mgba_force_gbp
mgba_frameskip
mgba_frameskip_interval
mgba_frameskip_threshold
mgba_gb_colors
mgba_gb_colors_preset
mgba_gb_model
mgba_idle_optimization
mgba_interframe_blending
mgba_sgb_borders
mgba_skip_bios
mgba_solar_sensor_level
mgba_use_bios"

    # Remove configurations from all files
    remove_config_entries "$GBA_GPSP_CFG_FILE" "$GBA_CFG_KEYS"
    remove_config_entries "$GBA_GPSP_GLSLP_FILE" "$GBA_GLSP_KEYS"
    remove_config_entries "$GBA_GPSP_GB_FILE" "$GBA_GPSP_OPT_KEYS"
    remove_config_entries "$GBA_MGBA_CFG_FILE" "$GBA_CFG_KEYS"
    remove_config_entries "$GBA_MGBA_GLSLP_FILE" "$GBA_GLSP_KEYS"
    remove_config_entries "$GBA_MGBA_GB_FILE" "$GBA_MGBA_OPT_KEYS"
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
