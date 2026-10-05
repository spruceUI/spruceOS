#!/bin/sh

TARGET_VERSION="4.5.2"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# The restore brings back pre-4.5.1 spruce shaders that leave alpha unset,
# which A133P draws as transparent. Set alpha to 1.0.
SHADER_DIR="/mnt/SDCARD/RetroArch/.retroarch/shaders/spruce/shaders"
for _name in TV dither gritty lcd svideo; do
    _shader="$SHADER_DIR/$_name.glsl"
    [ -f "$_shader" ] || continue
    grep -q "FragColor.a = 1.0\|FragColor = vec4(" "$_shader" && continue
    sed 's/FragColor\.rgb = \(.*\);/FragColor = vec4(\1, 1.0);/' "$_shader" > "$_shader.tmp" && mv "$_shader.tmp" "$_shader"
    log_message "Set alpha in $_shader"
done


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
