#!/bin/sh

chmod +x /mnt/SDCARD/spruce/scripts/save_poweroff.sh
# Forward PyUI's arguments (--repair-sd: the user consented to an fsck).
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot "$@"
