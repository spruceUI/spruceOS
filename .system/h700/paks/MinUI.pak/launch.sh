#!/bin/sh
#
# BaseOS hand-off shim  --  Anbernic RG XX (Allwinner H700) only.
#
# BaseOS (github.com/pvaibhav/BaseOS) replaces the Anbernic stock userland with
# a BusyBox rootfs on TF1 and hands control to a frontend by exec'ing exactly
# this path off the mounted card:
#
#   /etc/inittab  ->  /sbin/nextui-session  ->  $SD/.system/h700/paks/MinUI.pak/launch.sh
#
# and $SD is our TF2, because BaseOS mounts /dev/mmcblk1p1 in preference to its
# own TF1 volume. So dropping this file on a spruce card is enough to boot
# spruce under BaseOS with no change to BaseOS itself - which is the point:
# one TF1 card, and TF2 decides whether you get spruce or NextUI.
#
# The path is NextUI-shaped because NextUI is currently the only frontend
# BaseOS knows about. Its README says more may be added and PRODUCT.md commits
# to being frontend-neutral, so this is a stopgap until that script probes for
# a neutral entry point upstream. When it does, this file moves and nothing
# else on the spruce side changes.
#
# Caveat while it lives here: this is the same path NextUI's own installer
# writes. Do not expect a card to hold both frontends.
#
# Keep this dumb. Everything spruce-specific belongs in anbernic.sh.

exec /bin/sh /mnt/SDCARD/.tmp_update/anbernic.sh
