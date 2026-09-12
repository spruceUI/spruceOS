#!/bin/sh
#
# Moss hand-off shim  --  Powkiddy RGB30 only.
#
# Two different TF1 images can boot spruce on this device, and they enter at
# different paths:
#
#   MossySpruce (built)  spruce.service -> start_spruce.sh
#                        -> /mnt/SDCARD/.tmp_update/rgb30.sh          (direct)
#
#   Moss (modded)        minui.service -> start_minui.sh
#                        -> $SDCARD/.system/rgb30/paks/MinUI.pak/launch.sh
#                        -> this file -> .tmp_update/rgb30.sh
#
# The modded path exists because tools/mod-moss-image.sh in the MossySpruce
# repo deliberately changes only one thing in the stock image - the
# /mnt/SDCARD symlink - and leaves the frontend hand-off MinUI-shaped. Doing
# otherwise would mean rebuilding the distribution that the fallback exists to
# avoid.
#
# So this file is what makes a modded card boot. A built card never reads it,
# and having it costs nothing there.
#
# One caveat while it lives at this path: it is the same path MinUI's own
# installer writes. Do not expect a card to hold both frontends.
#
# Keep this dumb. Everything spruce-specific belongs in rgb30.sh.

exec /bin/sh /mnt/SDCARD/.tmp_update/rgb30.sh
