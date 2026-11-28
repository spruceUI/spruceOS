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

enable_spruce_context_buttons() {
    # Theme backups are copied over the installed configs after upgrades run.
    # Migrate both so restoring customizations keeps the new context buttons.
    for _cfg in /mnt/SDCARD/Themes/SPRUCE/config*.json \
        /mnt/SDCARD/Saves/spruce/theme_backups/SPRUCE/config*.json; do
        [ -f "$_cfg" ] || continue
        jq -e '.hint.contextbuttons == true' "$_cfg" >/dev/null 2>&1 && continue

        _tmp="$(mktemp "${_cfg}.tmp.XXXXXX")" || {
            log_message "Failed to create temporary file for $_cfg"
            _upgrade_warnings=1
            continue
        }
        if cp -p "$_cfg" "$_tmp" && jq '.hint.contextbuttons = true' "$_cfg" > "$_tmp" && mv -f "$_tmp" "$_cfg"; then
            log_message "Enabled context buttons in $_cfg"
        else
            rm -f "$_tmp"
            log_message "Failed to enable context buttons in $_cfg"
            _upgrade_warnings=1
        fi
    done
}

# Emulator_RGB30 was renamed Emulator_DARKMOSS. A restore copies selections by
# key, so the old key in a backup would be dropped and the choice lost.
rename_darkmoss_emulator_key() {
    _system="$1"
    for _cfg in "/mnt/SDCARD/Saves/spruce/emu_backups/$_system.json" "/mnt/SDCARD/Emu/$_system/config.json"; do
        [ -f "$_cfg" ] || continue
        jq -e '.menuOptions | has("Emulator_RGB30") and (has("Emulator_DARKMOSS") | not)' "$_cfg" >/dev/null || continue

        _tmp="$(mktemp "${_cfg}.tmp.XXXXXX")" || {
            log_message "Failed to create temporary file for $_cfg"
            _upgrade_warnings=1
            continue
        }
        if cp -p "$_cfg" "$_tmp" && jq '
            .menuOptions |= with_entries(if .key == "Emulator_RGB30" then .key = "Emulator_DARKMOSS" else . end)
        ' "$_cfg" > "$_tmp" && mv -f "$_tmp" "$_cfg"; then
            log_message "$_system: renamed Emulator_RGB30 to Emulator_DARKMOSS in $_cfg"
        else
            rm -f "$_tmp"
            log_message "Failed to rename Emulator_RGB30 in $_cfg"
            _upgrade_warnings=1
        fi
    done
}

# SSH host keys used to live beside the installed spruce payload. Move them
# into Saves so updates preserve the device's SSH host fingerprint. Never
# replace keys that were already generated in the new location.
migrate_ssh_host_keys() {
    _old_keys="/mnt/SDCARD/spruce/etc/ssh/keys"
    _new_keys="/mnt/SDCARD/Saves/ssh/keys"

    for _key_name in dropbear_rsa_host_key dropbear_ed25519_host_key; do
        [ -f "$_old_keys/$_key_name" ] || continue

        if [ -e "$_new_keys/$_key_name" ]; then
            log_message "SSH key migration: keeping existing $_new_keys/$_key_name"
            continue
        fi

        if ! mkdir -p "$_new_keys"; then
            log_message "SSH key migration: could not create $_new_keys"
            return 1
        fi

        if mv "$_old_keys/$_key_name" "$_new_keys/$_key_name"; then
            log_message "SSH key migration: moved $_key_name into Saves"
        else
            log_message "SSH key migration: failed to move $_key_name into Saves"
            return 1
        fi
    done
}

# Custom N64 remaps used to overwrite their shipped seed. Carry the restored
# user copy into Saves before future updates replace the seed.
migrate_n64_custom_remap() {
    _old_remap="/mnt/SDCARD/Emu/N64/remaps/Custom.rmp"
    _new_remap="/mnt/SDCARD/Saves/n64/Custom.rmp"

    [ -f "$_new_remap" ] && return 0
    [ -f "$_old_remap" ] || return 0

    mkdir -p "${_new_remap%/*}" || return 1
    cp -p "$_old_remap" "$_new_remap" || return 1
    log_message "N64 remap migration: copied Custom.rmp into Saves"
}

# PICO-8 writes its configuration, downloaded carts, and Splore metadata under
# .lexaloffle. Keep that mutable directory in Saves; the Emu copy is now only
# the seed for new installations.
migrate_pico8_data() {
    _old_data="/mnt/SDCARD/Emu/PICO8/.lexaloffle"
    _new_data="/mnt/SDCARD/Saves/.lexaloffle"

    [ -d "$_new_data" ] && return 0
    [ -d "$_old_data" ] || return 0

    mkdir -p "${_new_data%/*}" || return 1
    cp -a "$_old_data" "$_new_data" || return 1
    log_message "PICO-8 data migration: copied .lexaloffle into Saves"
}

# Flycast's standalone configuration is user state. The Emu directory now
# contains only defaults for new installations, so carry an existing live copy
# into Saves before a later update replaces the old location.
migrate_flycast_config() {
    _old_config="/mnt/SDCARD/Emu/DC/config/flycast"
    _new_config="/mnt/SDCARD/Saves/flycast"

    [ -d "$_new_config" ] && return 0
    [ -d "$_old_config" ] || return 0

    mkdir -p "${_new_config%/*}" || return 1
    cp -a "$_old_config" "$_new_config" || return 1
    log_message "Flycast config migration: copied configuration into Saves"
}

# vtree's config is user state. Leave the copy in App/FileManagement as the
# shipped seed and carry an existing edited copy into Saves.
migrate_filemanager_config() {
    _old_config="/mnt/SDCARD/App/FileManagement/config.ini"
    _new_config="/mnt/SDCARD/Saves/filemanager/config.ini"

    [ -f "$_new_config" ] && return 0
    [ -f "$_old_config" ] || return 0

    mkdir -p "${_new_config%/*}" || return 1
    cp -p "$_old_config" "$_new_config" || return 1
    log_message "File manager config migration: copied config.ini into Saves"
}

# The upgrade version stamp is user state. Move the legacy copy out of the App
# tree so future spruce updates cannot remove it.
migrate_last_update() {
    _old_stamp="/mnt/SDCARD/App/spruceRestore/.lastUpdate"
    _new_stamp="/mnt/SDCARD/Saves/spruce/.lastUpdate"

    [ -f "$_new_stamp" ] && return 0
    [ -f "$_old_stamp" ] || return 0

    mkdir -p "${_new_stamp%/*}" || return 1
    mv "$_old_stamp" "$_new_stamp" || return 1
    log_message "Upgrade version migration: moved .lastUpdate into Saves"
}

_upgrade_warnings=0
enable_spruce_context_buttons
if ! update_shader_presets; then
    log_message "Failed to update shader presets"
    _upgrade_warnings=1
fi
remove_replaced_lite_shaders
migrate_pokedaisy_selection GB pokedaisy_gbc
migrate_pokedaisy_selection GBC pokedaisy_gbc
migrate_pokedaisy_selection GBA pokedaisy_gba
for _system in DC N64 NDS PS SATURN; do
    rename_darkmoss_emulator_key "$_system"
done
if ! migrate_ssh_host_keys; then
    log_message "Failed to migrate SSH host keys"
    _upgrade_warnings=1
fi
if ! migrate_n64_custom_remap; then
    log_message "Failed to migrate the custom N64 remap"
    _upgrade_warnings=1
fi
if ! migrate_pico8_data; then
    log_message "Failed to migrate PICO-8 data"
    _upgrade_warnings=1
fi
if ! migrate_flycast_config; then
    log_message "Failed to migrate Flycast configuration"
    _upgrade_warnings=1
fi
if ! migrate_filemanager_config; then
    log_message "Failed to migrate file manager configuration"
    _upgrade_warnings=1
fi
if ! migrate_last_update; then
    log_message "Failed to migrate the upgrade version stamp"
    _upgrade_warnings=1
fi

# -------------------- UPGRADE COMPLETION --------------------
if [ "$_upgrade_warnings" -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
else
    log_message "Upgrade to version $TARGET_VERSION completed with warnings"
fi
exit 0
