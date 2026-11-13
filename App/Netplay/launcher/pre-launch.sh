#!/bin/sh
#
# Everything that has to happen before a wrapped emulator pak runs, in one
# place. Sourced, not executed - callers need the PATH change to survive.
#
# Three routes reach an emulator pak and all three need this identical
# preamble:
#
#   launch-stub.sh   legacy override written into Emus/<PLATFORM>/<TAG>.pak
#   bind-mount.sh    staged copy mounted over $SYSTEM_PATH/paks/Emus/<TAG>.pak
#   wrap-pak.sh      staged copy mounted over an EXTRAS pak on the SD path
#
# It lived in the first of those and was about to be copied into the other two.
# Three copies of "re-join the ad hoc network" is three places to fix it.
#
# Expects NETPLAY_PAK to be set by the caller.

: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${PLATFORM:=tg5040}"
: "${NETPLAY_PAK:=$SDCARD_PATH/Tools/$PLATFORM/Netplay.pak}"
# Exported for the minarch shadow and any launcher helpers it invokes.
export NETPLAY_PAK
. "$NETPLAY_PAK/launcher/state-path.sh"
. "$NETPLAY_PAK/launcher/wifi-platform.sh"

# A session cannot retain process or network ownership across a reboot. Clean
# that unambiguous leftover before deciding whether this launch is armed.
if [ -x "$NETPLAY_PAK/launcher/session-cleanup.sh" ]; then
	"$NETPLAY_PAK/launcher/session-cleanup.sh" || :
fi

# Nothing below costs anything without a session, so a stock launch is
# untouched - which is the whole point of leaving the mounts up permanently.
if [ -f "$NETPLAY_STATE/session" ]; then
	# Wi-Fi power save parks the radio between beacons: tens of milliseconds of
	# jitter on traffic as sparse as a few input bytes per frame. Re-applied
	# here rather than only at arm time because it comes back whenever the
	# interface reassociates. The app puts the prior value back on Turn off.
	# Only with "Disable Wi-Fi Power Saving" on, which is off by default.
	if grep -q '^disable_powersave=1$' "$NETPLAY_STATE/settings" 2>/dev/null; then
		np_powersave off || :
	fi

	# The app joins the ad hoc network when you pick a peer, but the platform
	# re-establishes its own WiFi once the app exits, so by the time a game
	# launches the device is back on the house network with the session still
	# pointing at the host's ad hoc address. Re-join here; a no-op when the
	# session is not ad hoc, or when we are already associated.
	if [ -x "$NETPLAY_PAK/launcher/adhoc-join.sh" ]; then
		"$NETPLAY_PAK/launcher/adhoc-join.sh" "$NETPLAY_STATE/session"
	fi
fi

# Put our minarch.elf shadow ahead of the real one. This is the entire
# mechanism: the original pak calls `minarch.elf` unqualified, so PATH decides
# which one runs, and ours loads the shim.
PATH="$NETPLAY_PAK/launcher:$PATH"
export PATH
