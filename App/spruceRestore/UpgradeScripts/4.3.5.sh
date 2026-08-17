#!/bin/sh

# Turn on RetroArch's software frame limiter for the Miyoo Mini family.
#
# Everything in here has to be safe to run more than once, because re-running is
# the normal case rather than an edge case. The updater deletes App/spruceRestore
# (it is in APP_DELETE_LIST in App/-Updater/delete_files.sh) before extracting,
# and .lastUpdate lives inside that folder. Nothing puts it back -- it is
# untracked, so it is not in the archive either. So after an in-device update
# there is no .lastUpdate, the runner falls back to 2.0.0, and every upgrade
# script runs again.
#
#
# What this fixes
#
# GBA ran at roughly three times its proper speed on the Miyoo Mini V4. Measured
# off a Sonic Advance in-game timer against wall clock: 14.45 seconds of game
# time in 4.90 seconds of real time, 2.95x.
#
# The Mini's platform config has video_vsync = "false", so audio_sync through the
# custom OSS driver was the only thing pacing the emulator. When that stops
# throttling, RetroArch free-runs at whatever the CPU manages, and gpSP on this
# hardware manages about 3x. It reads as a GBA fault only because GBA is light
# enough to exceed realtime -- heavier cores are CPU-bound near 1x anyway and so
# look normal.
#
# vrr_runloop_enable is RetroArch's third pacing option, badly named after G-Sync
# and FreeSync. It ignores both the display and the audio device and sleeps in
# software to hit the core's exact frame time. In runloop.c the frame limiter is
# gated on:
#
#   if (frame_limit_minimum_time && (vrr_runloop_enable || FASTMOTION
#                                    || (MENU && !vsync) || PAUSED))
#
# so with it off that limiter never ran during normal play at all -- only in
# fast-forward, menus or paused. Turning it on gives the Mini a throttle that
# does not depend on the audio device behaving. The Mini's RetroArch build also
# carries eggs' ffw_granularity_improvement patch, which sharpens the precision
# of that very sleep loop, so the better limiter was there all along and simply
# switched off.
#
# This does not explain why audio stopped pacing on the V4, and does not fix it.
# That is still worth chasing separately, since a silently failing audio throttle
# may be affecting more than emulation speed.
#
#
# Why an upgrade script is needed at all
#
# spruceBackup backs up RetroArch/platform/retroarch-MiyooMini.cfg (see its file
# list), and spruceRestore extracts the backup over / with `7zr x -y`. So a
# restore puts the user's old config straight back on top of the one the archive
# shipped, and the key would be lost again.
#
# The ordering works out: spruceRestore calls run_upgrade_scripts itself right
# after extracting, and .lastUpdate is inside the backup too -- so the restored,
# older version stamp makes this script count as newer and run, re-applying the
# key to the config that was just restored over it. That is also exactly why
# re-running has to be harmless.
#
# RetroArch is handed this file with --config and rewrites it itself, so a
# device's copy is not necessarily the one we shipped either.

TARGET_VERSION="4.3.5"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

MINI_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-MiyooMini.cfg"

# Matched literally, single spaces and all, the way 4.1.2.sh and 4.3.3.sh match
# keys in these files. Every upgrade script that has actually run on these
# devices sticks to plain anchored text and none of them use character classes,
# so this stays on the idiom that is known to work rather than betting on what
# the device's busybox was compiled with. RetroArch writes the line exactly this
# way when it saves the config.
VRR_OFF='^vrr_runloop_enable = "false"$'
VRR_ON='^vrr_runloop_enable = "true"$'

# The file ships on every device, not just the Minis -- the archive is one
# union of all of them. Editing it on a Brick or a Flip is harmless, since
# nothing but a Mini ever reads it, so there is no device check here.
if [ ! -f "$MINI_CFG" ]; then
    log_message "Mini frame limiter: $MINI_CFG not present, nothing to do"
elif grep -q "$VRR_ON" "$MINI_CFG"; then
    log_message "Mini frame limiter: vrr_runloop_enable already true, nothing to do"
elif ! grep -q "$VRR_OFF" "$MINI_CFG"; then
    # Neither value present. Do not append the key: a config without it has been
    # rewritten by something we do not know about, and guessing is worse than
    # leaving it be and saying so.
    log_message "Mini frame limiter: vrr_runloop_enable not found in $MINI_CFG, leaving it alone"
else
    if sed "s/$VRR_OFF/vrr_runloop_enable = \"true\"/" "$MINI_CFG" > "$MINI_CFG.tmp"; then
        mv "$MINI_CFG.tmp" "$MINI_CFG"
        log_message "Mini frame limiter: set vrr_runloop_enable to true in $MINI_CFG"
    else
        rm -f "$MINI_CFG.tmp"
        log_message "Mini frame limiter: could not rewrite $MINI_CFG, left unchanged"
    fi
fi

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
