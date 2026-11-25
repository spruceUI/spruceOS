#!/bin/bash

# Sourced by the launcher (needs GAMEDIR and SONGO_CFW_NAME). A CFW folder's
# setup.sh sets that CFW's default controls in songo.conf with
# songo_conf_default (from runtime/songo_conf.sh), using Godot names
# (JOY_BUTTON_A, KEY_ENTER, ...). Songo reads them for first launch and "Reset
# to Defaults". Controls the CFW doesn't set stay "default", Songo's built-in.

# The launcher sources songo_conf.sh first; this covers one that doesn't
command -v songo_conf_default > /dev/null || source "${GAMEDIR}/runtime/songo_conf.sh"

if [ -e "${GAMEDIR}/runtime/controls/${SONGO_CFW_NAME}/setup.sh" ]; then
	source "${GAMEDIR}/runtime/controls/${SONGO_CFW_NAME}/setup.sh"
fi
