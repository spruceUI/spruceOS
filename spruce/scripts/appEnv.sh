#!/bin/sh

# Environment contract for third-party Apps:
#
#   . /mnt/SDCARD/spruce/scripts/appEnv.sh
#
# Read the SPRUCE_* names set below and nothing else. The rest of spruce is
# internal and moves between releases - a copy of our device detection or of a
# config path is what leaves an app quietly broken one update later.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export CFW=SPRUCE
export SPRUCE_PLATFORM="$PLATFORM"

# Live RetroArch config. Editing RetroArch/platform/ instead has no effect:
# those are seeds, and RetroArch is launched with --config pointing here.
export SPRUCE_RA_CONFIG="$(ensure_ra_config_path)"

export SPRUCE_CONFIG="/mnt/SDCARD/Saves/spruce/spruce-config.json"
export SPRUCE_SHARED_CONFIG="/mnt/SDCARD/Saves/spruce/shared-system.json"
export SPRUCE_PYTHON="$(get_python_path)"

# An app with its own SDL2 should prefer these: several devices have no
# generic build that can reach the panel. Empty driver means "let SDL probe".
export SPRUCE_SDL2_DLL_PATH="$(get_sdl2_dll_path)"
export SPRUCE_SDL_VIDEODRIVER="$(get_sdl2_videodriver)"

# The boot hooks run long before PyUI, which is what normally exports TZ.
_app_tz="$(get_spruce_tz)"
[ -n "$_app_tz" ] && [ -z "${TZ:-}" ] && export TZ="$_app_tz"
unset _app_tz
