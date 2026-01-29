#!/bin/sh

# Exit on errors
set -e

# ---------- 1. Validate input ----------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <file_path>"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' does not exist."
    exit 1
fi

# ---------- 2. Extract system name from path (case-insensitive ROMS folder) ----------
SYSTEM_NAME=$(echo "$FILE" | awk -F'/(R|r)(O|o)(M|m)(S|s)/' '{print $2}' | cut -d'/' -f1)

if [ -z "$SYSTEM_NAME" ]; then
    echo "Error: Could not determine system name from path '$FILE'."
    exit 1
fi

# ---------- 3. Extract title (filename without directory or extension) ----------
TITLE=$(basename "$FILE")
TITLE="${TITLE%.*}"

# ---------- 4. Read assign.json and map to console/system ----------
ASSIGN_JSON="/opt/muos/share/info/assign/assign.json"
if [ ! -f "$ASSIGN_JSON" ]; then
    echo "Error: $ASSIGN_JSON not found."
    exit 1
fi

# Case-insensitive key lookup
CONSOLE=$(jq -r --arg key "$SYSTEM_NAME" '
    to_entries[]
    | select(.key | ascii_downcase == ($key | ascii_downcase))
    | .value
' "$ASSIGN_JSON")

if [ -z "$CONSOLE" ] || [ "$CONSOLE" = "null" ]; then
    echo "Error: No mapping found in assign.json for '$SYSTEM_NAME'."
    exit 1
fi

# ---------- 5. Read global.ini ----------
TARGET_DIR="/opt/muos/share/info/assign/$CONSOLE"
GLOBAL_INI="$TARGET_DIR/global.ini"

if [ ! -f "$GLOBAL_INI" ]; then
    echo "Error: $GLOBAL_INI not found."
    exit 1
fi

DEFAULT_VALUE=$(awk -F= '
    /\[global\]/ {found=1; next}
    /^\[/ && found {exit}
    found && $1=="default" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$GLOBAL_INI")

if [ -z "$DEFAULT_VALUE" ]; then
    echo "Error: Could not parse 'default' from $GLOBAL_INI"
    exit 1
fi

# ---------- 6. Find and parse default ini ----------
DEFAULT_FILE="$TARGET_DIR/${DEFAULT_VALUE}.ini"
if [ ! -f "$DEFAULT_FILE" ]; then
    echo "Error: Default ini file '$DEFAULT_FILE' not found."
    exit 1
fi

GOVERNOR_VALUE=$(awk -F= '
    /\[global\]/ {found=1; next}
    /^\[/ && found {exit}
    found && $1=="governor" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$DEFAULT_FILE")

if [ -z "$GOVERNOR_VALUE" ]; then
    GOVERNOR_VALUE=$(awk -F= '
        /\[global\]/ {found=1; next}
        /^\[/ && found {exit}
        found && $1=="governor" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
    ' "$GLOBAL_INI")

    if [ -z "$GOVERNOR_VALUE" ]; then
        echo "No governor found, using performance."
        GOVERNOR_VALUE="performance"
    fi
fi


CORE_VALUE=$(awk -F= -v section="$DEFAULT_VALUE" '
    $0 ~ "\\["section"\\]" {found=1; next}
    /^\[/ && found {exit}
    found && $1=="core" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$DEFAULT_FILE")

EXEC_VALUE=$(awk -F= '
    /\[launch\]/ {found=1; next}
    /^\[/ && found {exit}
    found && $1=="exec" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}
' "$DEFAULT_FILE")

if [ -z "$CORE_VALUE" ] || [ -z "$EXEC_VALUE" ]; then
    echo "Error: Could not parse core or exec from $DEFAULT_FILE"
    exit 1
fi

# ---------- 7. Check for per-game overrides in /mnt/mmc/MUOS/info/core ----------
# 1) Extract relative path after ROMS/ (e.g., "N64/SubFolder/Game.z64")
RELATIVE_PATH=$(echo "$FILE" | awk -F'/(R|r)(O|o)(M|m)(S|s)/' '{print $2}')

# 2) Build equivalent folder structure under /mnt/mmc/MUOS/info/core
CORE_BASE="/opt/muos/share/info/core/$RELATIVE_PATH"
CORE_DIR=$(dirname "$CORE_BASE")
echo "CORE_DIR: $CORE_DIR"

# Ensure directory exists before checking files
if [ -d "$CORE_DIR" ]; then
    GAME_BASENAME="${TITLE}"

    # --- Core override files ---
    CFG_GAME="$CORE_DIR/${GAME_BASENAME}.cfg"   # Highest priority
    CFG_CORE="$CORE_DIR/${CORE_VALUE}.cfg"      # Middle priority
    CFG_SYSTEM="$CORE_DIR/core.cfg"   # Lowest priority

    # --- Governor override files ---
    GOV_GAME="$CORE_DIR/${GAME_BASENAME}.gov"   # Highest priority
    GOV_CORE="$CORE_DIR/${CORE_VALUE}.gov"      # Middle priority
    GOV_SYSTEM="$CORE_DIR/core.gov"   # Lowest priority

    # Helper function to safely read the core value (second line only)
    read_core_from_cfg() {
        local cfg_file="$1"
        sed -n '1p' "$cfg_file" | tr -d '\r\n'
    }

    # Helper function to read governor value (entire file, trim CRLF)
    read_gov_from_file() {
        local gov_file="$1"
        tr -d '\r\n' < "$gov_file"
    }

    # ---------- CORE override priority check ----------
    if [ -f "$CFG_GAME" ]; then
        NEW_CORE=$(read_core_from_cfg "$CFG_GAME")
    elif [ -f "$CFG_CORE" ]; then
        NEW_CORE=$(read_core_from_cfg "$CFG_CORE")
    elif [ -f "$CFG_SYSTEM" ]; then
        NEW_CORE=$(read_core_from_cfg "$CFG_SYSTEM")
    else
        NEW_CORE=""
    fi

    if [ -n "$NEW_CORE" ]; then
        CORE_VALUE="$NEW_CORE"
    fi

    # ---------- GOVERNOR override priority check ----------
    if [ -f "$GOV_GAME" ]; then
        NEW_GOV=$(read_gov_from_file "$GOV_GAME")
    elif [ -f "$GOV_CORE" ]; then
        NEW_GOV=$(read_gov_from_file "$GOV_CORE")
    elif [ -f "$GOV_SYSTEM" ]; then
        NEW_GOV=$(read_gov_from_file "$GOV_SYSTEM")
    else
        NEW_GOV=""
    fi

    if [ -n "$NEW_GOV" ]; then
        GOVERNOR_VALUE="$NEW_GOV"
    fi
fi

# ---------- 8. Governor handling ----------
CONFIG_FILE="/opt/muos/device/config/cpu/governor"

if [ ! -r "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found or not readable."
    echo "Skipping governor changes."
    GOV_ENABLED=false
else
    # Read the first line, remove any carriage returns
    GOVERNOR_FILE=$(tr -d '\r' < "$CONFIG_FILE" | sed -n '1p')

    if [ -z "$GOVERNOR_FILE" ]; then
        echo "Error: Governor file path inside '$CONFIG_FILE' is empty."
        echo "Skipping governor changes."
        GOV_ENABLED=false
    elif [ ! -f "$GOVERNOR_FILE" ]; then
        echo "Error: Governor target file '$GOVERNOR_FILE' does not exist."
        echo "Skipping governor changes."
        GOV_ENABLED=false
    elif [ ! -r "$GOVERNOR_FILE" ] || [ ! -w "$GOVERNOR_FILE" ]; then
        echo "Error: Governor file '$GOVERNOR_FILE' is not readable or writable."
        echo "Skipping governor changes."
        GOV_ENABLED=false
    else
        GOV_ENABLED=true
    fi
fi

# ---------- 9. Cache the current governor ----------
if [ "$GOV_ENABLED" = true ]; then
    ORIGINAL_GOVERNOR=$(cat "$GOVERNOR_FILE" 2>/dev/null)
    if [ -z "$ORIGINAL_GOVERNOR" ]; then
        echo "Warning: Unable to read current governor value from '$GOVERNOR_FILE'."
        echo "Skipping governor changes."
        GOV_ENABLED=false
    fi
fi

# ---------- 10. Final output logging ----------
echo "System Name: $SYSTEM_NAME"
echo "Console: $CONSOLE"
echo "Governor: $GOVERNOR_VALUE"
echo "Original Governor: $ORIGINAL_GOVERNOR"
echo "Governor File Path: $GOVERNOR_FILE"
echo "Core: $CORE_VALUE"
echo "Exec: $EXEC_VALUE"
echo "Title: $TITLE"

# ---------- 11. Handle ra_no_load toggle ----------
if [ "$CORE_VALUE" = "km_ludicrousn64_2k22_xtreme_amped_libretro.so" ]; then
    touch /tmp/ra_no_load
else
    rm -f /tmp/ra_no_load
fi

# ---------- 12. Apply new governor ----------
if [ "$GOV_ENABLED" = true ]; then
    echo "Setting governor to \"$GOVERNOR_VALUE\""
    echo "$GOVERNOR_VALUE" > "$GOVERNOR_FILE"
else
    echo "Governor change skipped."
fi

# ---------- 13. Execute the command ----------
echo "Executing: $EXEC_VALUE \"$TITLE\" \"$CORE_VALUE\" \"$FILE\""
exec "$EXEC_VALUE" "$TITLE" "$CORE_VALUE" "$FILE"

# ---------- 14. Restore original governor ----------
if [ "$GOV_ENABLED" = true ]; then
    echo "Restoring governor to \"$ORIGINAL_GOVERNOR\""
    echo "$ORIGINAL_GOVERNOR" > "$GOVERNOR_FILE"
else
    echo "Governor restore skipped."
fi
