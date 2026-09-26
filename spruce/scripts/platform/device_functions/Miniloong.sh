#!/bin/sh
# Miniloong Pocket 1 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The jack is not an extcon here; ask the codec. UNVERIFIED under dArkMoss.
are_headphones_plugged_in() {
    amixer cget numid=1 2>/dev/null | grep -q 'values=on'
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

# The rk817 is configured to power-cycle every rail on a SoC reset, so a plain
# reboot never comes back. SYS_CFG3 bits 7:6 set to "reset registers only"
# right before the reboot makes it return. Needs i2c-tools on the base.
device_prepare_for_reboot() {
    command -v i2cset >/dev/null 2>&1 || { log_message "Miniloong: i2cset missing, rk817 left as is"; return 0; }
    _cur="$(i2cget -f -y 0 0x20 0xf4 2>/dev/null)"
    case "$_cur" in 0x[0-9a-fA-F][0-9a-fA-F]) ;; *) _cur=0x18 ;; esac
    _new=$(( (_cur & 0x3f) | 0x40 ))
    i2cset -f -y 0 0x20 0xf4 "$_new" 2>/dev/null
    log_message "Miniloong: rk817 SYS_CFG3 $_cur -> $(printf '0x%02x' "$_new") before reboot"
}
