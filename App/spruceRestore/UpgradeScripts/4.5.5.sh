#!/bin/sh

TARGET_VERSION="4.5.5"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# dArkMoss system jsons moved from App/PyUI/config to Saves. Overwrite: boot may
# already have seeded a default there.
OLD_CONFIG_DIR=/mnt/SDCARD/App/PyUI/config
for _name in rgb30 rgb20sx miniloong a10mini g350 xumini; do
    _old="$OLD_CONFIG_DIR/$_name-system.json"
    [ -f "$_old" ] || continue
    mv -f "$_old" "/mnt/SDCARD/Saves/$_name-system.json" && log_message "Moved $_old to Saves"
done
rmdir "$OLD_CONFIG_DIR" 2>/dev/null || true

# Miyoo Mini system json renamed. Overwrite: boot may already have seeded a default.
if [ -f /mnt/SDCARD/Saves/mini-flip-system.json ]; then
    mv -f /mnt/SDCARD/Saves/mini-flip-system.json /mnt/SDCARD/Saves/miyoo-mini-system.json && log_message "Renamed mini-flip-system.json to miyoo-mini-system.json"
fi

# A restore puts back every saved "selected", so a changed default whose old value
# is still an option needs moving in the backup, or the old default wins.
migrate_selected() {
    _cfg="/mnt/SDCARD/Saves/spruce/emu_backups/$1.json"
    [ -f "$_cfg" ] || return 0
    [ "$(jq -r --arg k "$2" '.menuOptions[$k].selected // ""' "$_cfg")" = "$3" ] || return 0
    jq --arg k "$2" --arg v "$4" '.menuOptions[$k].selected = $v' "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
    log_message "$1 $2: $3 -> $4"
}

migrate_selected GAMETANK Emulator_A30 gametank-standalone gametank
migrate_selected GAMETANK Emulator_64 gametank-standalone gametank
migrate_selected GAMETANK Governor Performance Smart
migrate_selected DC Emulator_RGB30 Flycast-standalone Flycast-libretro
migrate_selected SATURN Emulator_RGB30 yabasanshiro-standalone-hle yabasanshiro_generic_libretro
migrate_selected N64 controlMode Custom "Spruce (per device)"

# Emu/NDS/usrcheat.dat was a duplicate of Emu/NDS/cheats/usrcheat.dat and is gone.
for _ini in /mnt/SDCARD/Saves/dsperate/*.ini; do
    [ -f "$_ini" ] || continue
    sed -i 's|^cheats = /mnt/SDCARD/Emu/NDS/usrcheat.dat$|cheats = /mnt/SDCARD/Emu/NDS/cheats/usrcheat.dat|' "$_ini"
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
