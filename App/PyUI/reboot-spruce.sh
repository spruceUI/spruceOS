#!/bin/sh

chmod +x /mnt/SDCARD/spruce/scripts/save_poweroff.sh
# Forward any arguments (save_poweroff.sh still understands --repair-sd).
/mnt/SDCARD/spruce/scripts/save_poweroff.sh --reboot "$@"
