#!/bin/sh

# We control wpa_supplicant, not the system
systemctl stop wpa_supplicant
systemctl disable wpa_supplicant
systemctl mask wpa_supplicant

/mnt/SDCARD/spruce/scripts/runtime.sh
