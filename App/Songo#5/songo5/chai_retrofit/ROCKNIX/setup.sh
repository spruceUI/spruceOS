#!/bin/sh
# CHAI retrofit setup: ROCKNIX
#
# Usage: setup.sh setup|teardown
#
# ROCKNIX runs PipeWire, so the default wpctl/pactl wrapper covers volume.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

chai_setup_main "$@"
