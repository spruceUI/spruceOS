#!/bin/sh

# Remove the E-Reader's old private copy of the SDL 1.2-era library set.
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
# What this cleans up
#
# App/PixelReader/libXX/ held libSDL_image-1.2, libSDL_ttf-2.0 and their
# dependency closure for the Anbernic XX line, which has them in neither BaseOS
# nor the stock Anbernic image. The Gallery links exactly the same set, so
# rather than ship a second 8 MB copy the libraries moved to
# spruce/h700/lib64/ and both apps now point there.
#
# The updater extracts over the existing card without removing files that are no
# longer in the archive, so the old folder stays behind: ~11 MB of libraries
# nothing loads any more. Nothing breaks if it survives -- both launchers name
# the new path outright and never look in libXX -- so this is purely reclaiming
# space, which is why it is safe to be this blunt about it.
#
# Deliberately narrow: only this one known-dead directory, matched in full. It
# is not a general "clean up App/PixelReader" pass, because a wildcard there
# could take out something a user put on their own card.

TARGET_VERSION="4.3.6"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

OLD_LIB_DIR="/mnt/SDCARD/App/PixelReader/libXX"

if [ -d "$OLD_LIB_DIR" ]; then
    # Only remove it once the replacement is actually in place. If an update
    # landed badly and spruce/h700/lib64 is missing, leaving the old copy alone
    # keeps the E-Reader working rather than breaking it to save disk.
    if [ -f "/mnt/SDCARD/spruce/h700/lib64/libSDL_image-1.2.so.0" ]; then
        rm -rf "$OLD_LIB_DIR"
        log_message "4.3.6: removed superseded $OLD_LIB_DIR (now spruce/h700/lib64)"
    else
        log_message "4.3.6: kept $OLD_LIB_DIR -- spruce/h700/lib64 is missing"
    fi
else
    log_message "4.3.6: no $OLD_LIB_DIR to remove, nothing to do"
fi

# The runner treats a non-zero exit as a failed upgrade and stops the whole
# chain, so end deliberately rather than inheriting the status of whatever ran
# last. Nothing above is fatal: the worst case is that a dead folder survives.
exit 0
