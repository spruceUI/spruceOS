#!/bin/sh

TARGET_VERSION="4.6.1"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Shader preset files with "lite" in the name were renamed to use "fast" instead.
# Update any user-saved RetroArch shader presets to use the new paths.
#
# This includes:
#   - .glslp, .slangp, .cgp preset files in Saves/retroarch/ and its subdirs
#   - References to armgba shader files (e.g., armgba-lcd-lite.glsl -> armgba-lcd-fast.glsl)
#
# The script safely handles multiple runs since all replacements are idempotent:
# if a preset already uses "fast", replacing "lite" with "fast" again does nothing.

update_shader_presets() {
    _presets_dir="/mnt/SDCARD/Saves/retroarch"
    
    if [ ! -d "$_presets_dir" ]; then
        log_message "No user-saved retroarch presets found (directory does not exist)"
        return 0
    fi
    
    # Find all preset files and update them
    find "$_presets_dir" -type f \( -name "*.glslp" -o -name "*.slangp" -o -name "*.cgp" \) | while read -r _preset; do
        # Skip if file doesn't exist (shouldn't happen, but be safe)
        [ -f "$_preset" ] || continue
        
        # Check if file contains any "lite" references we should update
        if grep -q "lite" "$_preset"; then
            # Create a backup just in case
            cp "$_preset" "$_preset.bak"
            
            # Replace all armgba-*-lite shader references with -fast equivalents
            sed -i 's/armgba-lcd-fade-lite\.glsl/armgba-lcd-fade-fast.glsl/g' "$_preset"
            sed -i 's/armgba-lcd-lite\.glsl/armgba-lcd-fast.glsl/g' "$_preset"
            
            # Replace preset file references (in case user renamed the presets themselves)
            sed -i 's/armgba-lcd-gba-lite\.glslp/armgba-lcd-gba-fast.glslp/g' "$_preset"
            sed -i 's/armgba-lcd-gbc-lite\.glslp/armgba-lcd-gbc-fast.glslp/g' "$_preset"
            sed -i 's/armgba-lcd-gb-gray-lite\.glslp/armgba-lcd-gb-gray-fast.glslp/g' "$_preset"
            sed -i 's/armgba-lcd-gb-light-lite\.glslp/armgba-lcd-gb-light-fast.glslp/g' "$_preset"
            sed -i 's/armgba-lcd-gb-lite\.glslp/armgba-lcd-gb-fast.glslp/g' "$_preset"
            sed -i 's/armgba-lcd-gb-pocket-lite\.glslp/armgba-lcd-gb-pocket-fast.glslp/g' "$_preset"
            
            # Check if any changes were actually made
            if ! diff -q "$_preset" "$_preset.bak" >/dev/null 2>&1; then
                log_message "Updated shader preset: ${_preset#/mnt/SDCARD/}"
                rm -f "$_preset.bak"
            else
                # No changes made, remove backup
                rm -f "$_preset.bak"
            fi
        fi
    done
}

remove_replaced_lite_shaders() {
    _shader_dir="/mnt/SDCARD/RetroArch/.retroarch/shaders/armgba"
    for _relative in \
        shaders/armgba-lcd-fade-lite.glsl \
        shaders/armgba-lcd-lite.glsl \
        armgba-lcd-gba-lite.glslp \
        armgba-lcd-gbc-lite.glslp \
        armgba-lcd-gb-gray-lite.glslp \
        armgba-lcd-gb-light-lite.glslp \
        armgba-lcd-gb-lite.glslp \
        armgba-lcd-gb-pocket-lite.glslp; do
        _lite="$_shader_dir/$_relative"
        _fast="${_lite%-lite.*}-fast.${_lite##*.}"
        [ -f "$_lite" ] && [ -f "$_fast" ] || continue
        if rm -f "$_lite"; then
            log_message "Removed replaced shader file: $_lite"
        else
            log_message "Failed to remove replaced shader file: $_lite"
            _upgrade_warnings=1
        fi
    done
}

migrate_pokedaisy_selection() {
    _system="$1"
    _core="$2"
    for _cfg in "/mnt/SDCARD/Saves/spruce/emu_backups/$_system.json" "/mnt/SDCARD/Emu/$_system/config.json"; do
        [ -f "$_cfg" ] || continue

        jq -e '
            .menuOptions.Emulator |
            (.selected == "pokedaisy") or
            ((.overrides | type == "object") and any(.overrides[]; . == "pokedaisy"))
        ' "$_cfg" >/dev/null
        _status=$?
        case "$_status" in
            1) continue ;;
            0) ;;
            *)
                log_message "Failed to inspect PokeDaisy selections in $_cfg"
                _upgrade_warnings=1
                continue
                ;;
        esac

        _tmp="$(mktemp "${_cfg}.tmp.XXXXXX")" || {
            log_message "Failed to create temporary file for $_cfg"
            _upgrade_warnings=1
            continue
        }
        if cp -p "$_cfg" "$_tmp" && jq --arg core "$_core" '
            .menuOptions.Emulator |= (
                if .selected == "pokedaisy" then .selected = $core else . end |
                if (.overrides | type) == "object" then
                    .overrides |= map_values(if . == "pokedaisy" then $core else . end)
                else . end
            )
        ' "$_cfg" > "$_tmp" && mv -f "$_tmp" "$_cfg"; then
            log_message "$_system: migrated PokeDaisy selections to $_core in $_cfg"
        else
            rm -f "$_tmp"
            log_message "Failed to migrate PokeDaisy selections in $_cfg"
            _upgrade_warnings=1
        fi
    done
}

_upgrade_warnings=0
if ! update_shader_presets; then
    log_message "Failed to update shader presets"
    _upgrade_warnings=1
fi
remove_replaced_lite_shaders
migrate_pokedaisy_selection GB pokedaisy_gbc
migrate_pokedaisy_selection GBC pokedaisy_gbc
migrate_pokedaisy_selection GBA pokedaisy_gba

# -------------------- UPGRADE COMPLETION --------------------
if [ "$_upgrade_warnings" -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
else
    log_message "Upgrade to version $TARGET_VERSION completed with warnings"
fi
exit 0
