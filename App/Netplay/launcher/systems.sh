#!/bin/sh
#
# What spruce runs for a system, asked the way spruce's own launcher asks it.
#
#   systems.sh core <TAG>    the core spruce selects for the system, as
#                            "<name>" (libretro, without _libretro.so) or the
#                            emulator's own name; nothing, exit 1, if spruce has
#                            no such system
#
# TAG is Netplay's system tag, as NextUI names its paks; the few spruce names
# differently are mapped here.

[ "$1" = core ] && [ -n "$2" ] || { echo "usage: systems.sh core <TAG>" >&2; exit 2; }
case "$2" in
	32X)    tag=THIRTYTWOX ;;
	SMS)    tag=MS ;;
	SG1000) tag=SEGASGONE ;;
	*)      tag=$2 ;;
esac

EMU_NAME="$tag"
EMU_DIR="/mnt/SDCARD/Emu/$tag"
EMU_JSON_PATH="$EMU_DIR/config.json"
[ -f "$EMU_JSON_PATH" ] || exit 1
export EMU_NAME EMU_DIR EMU_JSON_PATH

# Sourced for set_emu_core_from_emu_json and the device it resolves against.
# Both log, and nothing of theirs belongs in the answer.
{
	. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
	. /mnt/SDCARD/spruce/scripts/emu/lib/general_functions.sh
	RA_BUILD="$(get_effective_ra_build)"
	export RA_BUILD
	set_emu_core_from_emu_json
	if [ -z "$CORE" ] || [ "$CORE" = "null" ]; then use_default_emulator; fi
} >/dev/null 2>&1
[ -n "$CORE" ] && [ "$CORE" != "null" ] || exit 1
echo "$CORE"
