#!/bin/sh
#
# Where Netplay lives on spruce, and which NextUI platform build this device
# runs. Sourced by every spruce entry point - the app's launch.sh, the RetroArch
# shadow and the mount hook - before anything from common/.
#
# spruce names devices itself (Brick, AnbernicXX640480, ...); Netplay's binaries
# are built per NextUI platform, and one of those covers each device spruce runs
# on the same hardware. A device not listed here has no build.

: "${SDCARD_PATH:=/mnt/SDCARD}"
NETPLAY_FIRMWARE=spruce
NETPLAY_PAK="$SDCARD_PATH/App/Netplay"
NETPLAY_STATE="$SDCARD_PATH/Saves/netplay"
NETPLAY_LOGS="$NETPLAY_STATE/logs"
export SDCARD_PATH NETPLAY_FIRMWARE NETPLAY_PAK NETPLAY_STATE NETPLAY_LOGS

# spruce's own device name, from its helperFunctions.sh, to Netplay's platform.
np_spruce_platform() {
	case "$1" in
		Brick|BrickPro|SmartPro) echo tg5040 ;;
		SmartProS)               echo tg5050 ;;
		Anbernic*)               echo h700 ;;
		Flip)                    echo my355 ;;
		A30|MIYOO_A30)           echo my282 ;;
		MiyooMini)               echo my285 ;;
		*)
			# Every dArkMoss unit runs the my355 build (plain AArch64, RK3566
			# and RK3326 alike). helperFunctions.sh sets PLATFORM_FAMILY
			# without exporting it, so a process spruce starts (the DS
			# shadow) looks at the image the way helperFunctions.sh does.
			[ "${PLATFORM_FAMILY:-}" = darkmoss ] ||
				grep -q '^OS_NAME="DARKMOSS"' "${NETPLAY_OS_RELEASE:-/etc/os-release}" 2>/dev/null ||
				return 1
			echo my355
			;;
	esac
}

