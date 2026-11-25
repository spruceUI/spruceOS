#!/bin/bash

# Sourced by the launcher (needs GAMEDIR), before anything that writes to
# songo.conf. Songo finds songo.conf beside its runtime (GAMEDIR/songo.conf, as
# the runtime is in GAMEDIR/runtime) and reads it at launch (see SongoConf).
#
# The launcher works out its songo.conf values on the first launch only: once
# they're written, songo_conf_mark_built creates songo_configs_built next to
# songo.conf, and from then on the writers below do nothing. Deleting
# songo_configs_built has them worked out again on the next launch.
#
#   songo_conf_building               true until songo_configs_built exists,
#                                     to skip work that only feeds songo.conf
#   songo_conf_set <key> <value>      writes the value
#   songo_conf_default <key> <value>  only where songo.conf still says
#                                     "default", so a value set by hand is kept
#   songo_conf_mark_built             creates songo_configs_built, after the
#                                     last write
#
# Either writer adds the key if it's missing from the file. Nothing is written
# (or marked built) when there's no songo.conf. ESUDO is PortMaster's sudo
# where the port folder needs it (unset under spruce).

SONGO_CONF="${GAMEDIR}/songo.conf"
SONGO_CONF_BUILT="${GAMEDIR}/songo_configs_built"

songo_conf_building() {
	[ -f "$SONGO_CONF" ] && [ ! -e "$SONGO_CONF_BUILT" ]
}

songo_conf_set() { # <key> <value>
	_songo_conf_write "$1" "$2" ".*"
}

songo_conf_default() { # <key> <value>
	_songo_conf_write "$1" "$2" "default[[:space:]]*"
}

songo_conf_mark_built() {
	songo_conf_building || return 0
	$ESUDO touch "$SONGO_CONF_BUILT"
}

# Replaces <key>'s line where its value matches <value pattern> (a sed regex),
# or adds the key if the file doesn't have it
_songo_conf_write() { # <key> <value> <value pattern>
	songo_conf_building || return 0
	if grep -q "^[[:space:]]*$1[[:space:]]*=" "$SONGO_CONF"; then
		# [[:space:]]* before the end also matches a \r from a file saved on Windows
		$ESUDO sed -i "s|^[[:space:]]*$1[[:space:]]*=[[:space:]]*$3$|$1=$2|" "$SONGO_CONF"
	else
		printf '%s=%s\n' "$1" "$2" | $ESUDO tee -a "$SONGO_CONF" > /dev/null
	fi
}
