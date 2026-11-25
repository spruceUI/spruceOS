#!/bin/bash

# Sourced by Songo5.sh (needs CFW_NAME from PortMaster), exports SONGO_CFW_NAME:
# the strategy folder name the controls runtime scripts use. Brightness,
# battery, volume and idle suppression go through chai_retrofit instead.

# Detect CFW, used to pick the runtime strategies
SONGO_CFW_NAME="NONE"
if [[ "$CFW_NAME" = "knulli" ]]; then
	# Scarab onwards ships knulli.version, pre-Scarab only batocera.version
	if [ -f /usr/share/knulli/knulli.version ]; then
		SONGO_CFW_NAME="knulli"
	else
		SONGO_CFW_NAME="knulli_pre_scarab"
	fi
elif [[ "$CFW_NAME" = "muOS" ]]; then
	# Version is YYMM.N_CODENAME, Andromeda is 2606. Missing or unreadable
	# means a release older than the version file.
	MUOS_VERSION="$(cat /opt/muos/config/system/version 2>/dev/null)"
	MUOS_VERSION_MAJOR="${MUOS_VERSION%%.*}"
	if [[ "$MUOS_VERSION_MAJOR" =~ ^[0-9]+$ ]] && [ "$MUOS_VERSION_MAJOR" -ge 2606 ]; then
		SONGO_CFW_NAME="muOS"
	else
		SONGO_CFW_NAME="muOS_pre_andromeda"
	fi
elif [[ "$CFW_NAME" = "ROCKNIX" ]]; then
	SONGO_CFW_NAME="${CFW_NAME}"
elif [ -f /mnt/SDCARD/.system/version.txt ] && grep -q "NextUI" /mnt/SDCARD/.system/version.txt; then
	SONGO_CFW_NAME="NextUI"
elif [ -f /mnt/SDCARD/spruce/spruce ]; then
	SONGO_CFW_NAME="Spruce"
fi
export SONGO_CFW_NAME
