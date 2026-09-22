#!/bin/sh

# Environment contract for third-party Apps. Read the SPRUCE_* names and
# nothing else; the rest of spruce moves between releases.
#
#   . /mnt/SDCARD/spruce/scripts/appEnv.sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export CFW=SPRUCE
export SPRUCE_PLATFORM="$PLATFORM"
export SPRUCE_PYTHON="$(get_python_path)"

# Editing RetroArch/platform instead has no effect: RetroArch is launched with
# --config pointing here.
export SPRUCE_RA_CONFIG="$(ensure_ra_config_path)"
