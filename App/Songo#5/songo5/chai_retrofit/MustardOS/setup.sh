#!/bin/sh
# CHAI retrofit setup: muOS
#
# Usage: setup.sh setup|teardown
#
# All muOS volume changes go through wpctl (device/audio.sh SET_CURRENT on
# Andromeda), so the default PipeWire wrapper covers both version ranges.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

chai_setup_main "$@"
