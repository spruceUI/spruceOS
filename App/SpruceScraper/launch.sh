#!/bin/sh
# Spruce Scraper launcher (spruceOS). PyUI has already exited when this runs: principal.sh runs
# /tmp/cmd_to_run.sh and restarts PyUI when we return, and PyUI then converts the new box art
# (App/PyUI/pyui_resize_boxart_trigger). Structure follows Aesthetic Spruce's launcher.
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$APP_DIR/.scraper"
# settings, logs and Skyscraper's work folder: under Saves/ like spruce's other apps, so an
# update never touches them
USERDATA_DIR="/mnt/SDCARD/Saves/SpruceScraper"
LOG_DIR="$USERDATA_DIR/logs"
mkdir -p "$LOG_DIR"
SESSION_LOG_FILE="$LOG_DIR/$(date +%Y%m%d_%H%M%S).log"
# keep the last few sessions only
ls -1t "$LOG_DIR"/*.log 2>/dev/null | tail -n +6 | xargs -r rm -f

log_message "Spruce Scraper: starting on $PLATFORM (${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} rot ${DISPLAY_ROTATION:-0})"

export WIDTH="$DISPLAY_WIDTH"
export HEIGHT="$DISPLAY_HEIGHT"
export ROTATION="${DISPLAY_ROTATION:-0}"
export ROOT_DIR="$APP_DIR"
export SOURCE_DIR
export SCRAPER_USERDATA="$USERDATA_DIR"
export SPRUCE_PLATFORM="$PLATFORM"
export SPRUCE_SYSTEM_JSON="$SYSTEM_JSON"
export SPRUCE_VERSION="$(get_version 2>/dev/null)"

# the ROM folders PyUI reads: this card, and a second card when one is mounted
ROMS_DIRS="/mnt/SDCARD/Roms"
[ -d /media/sdcard1/Roms ] && ROMS_DIRS="$ROMS_DIRS:/media/sdcard1/Roms"
export SCRAPER_ROMS_DIRS="$ROMS_DIRS"
export SCRAPER_EMU_DIR="/mnt/SDCARD/Emu"
export SCRAPER_PYUI_TRIGGER="/mnt/SDCARD/App/PyUI/pyui_resize_boxart_trigger"
export SCRAPER_CA_FILE="/mnt/SDCARD/spruce/etc/ca-certificates.crt"

# spruce's python runs tools/ptyrun.py, which makes Skyscraper's progress live. get_python_path
# (platform/common64bit.sh) names spruce/flip/bin/python3.10: the python3 next to it is a git
# symlink, which a FAT card does not keep.
for py in "$(get_python_path 2>/dev/null)" /mnt/SDCARD/spruce/flip/bin/python3.10 "$(command -v python3 2>/dev/null)"; do
    if [ -n "$py" ] && [ -x "$py" ]; then
        export SCRAPER_PYTHON="$py"
        break
    fi
done

# Skyscraper needs only firmware libraries and runs with an empty library path (scraper/skyenv.lua);
# a bundle with its own lib/ would get that folder and then this platform's path, not LÖVE's
export SCRAPER_BASE_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
# liblove/luajit ship with the app and must win; lib/fallback only fills gaps, so it goes last
export LD_LIBRARY_PATH="$SOURCE_DIR/lib:$LD_LIBRARY_PATH:$SOURCE_DIR/lib/fallback"

# SDL video per platform, mirroring App/PyUI/launch.sh
case "$PLATFORM" in
    Miniloong | RGB30)
        export SDL_VIDEODRIVER=kmsdrm
        ;;
    Anbernic*)
        export SDL_JOYSTICK_DISABLE_UDEV=1
        if [ -f /mnt/SDCARD/App/PyUI/dll-mali/libSDL2-2.0.so.0 ]; then
            export LD_LIBRARY_PATH="/mnt/SDCARD/App/PyUI/dll-mali:$LD_LIBRARY_PATH"
            export SDL_VIDEODRIVER=mali
        fi
        ;;
esac

export_sdl_gamecontroller_map

# Button labels: SDL's built-in maps are positional, these devices print Nintendo labels.
# Same table as Aesthetic Spruce, measured there on each device.
case "$PLATFORM" in
    Brick | BrickOakMOSS | BrickPro | SmartPro | SmartProS | Flip | Zero28 | Zero40 | XU20)
        export SCRAPER_SWAP_AB=1 SCRAPER_SWAP_XY=1 ;;
    Miniloong | Pixel2)
        export SCRAPER_SWAP_AB=1 ;;
esac

cd "$SOURCE_DIR" || exit 1
chmod +x ./bin/love ./skyscraper/Skyscraper 2>/dev/null
./bin/love . >> "$SESSION_LOG_FILE" 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" != 0 ] && [ -f "$USERDATA_DIR/last_crash.txt" ] && [ "$USERDATA_DIR/last_crash.txt" -nt "$SESSION_LOG_FILE" ]; then
    log_message "Spruce Scraper crashed: $(sed -n 2p "$USERDATA_DIR/last_crash.txt" | cut -c1-200)"
fi
log_message "Spruce Scraper: exited with $EXIT_CODE"
exit 0
