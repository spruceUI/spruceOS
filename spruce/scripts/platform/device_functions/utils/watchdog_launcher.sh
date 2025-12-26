#!/bin/sh

launch_common_startup_watchdogs(){
    ${SCRIPTS_DIR}/powerbutton_watchdog.sh &
    ${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &
    ${SCRIPTS_DIR}/low_power_warning.sh &
    ${SCRIPTS_DIR}/homebutton_watchdog.sh &
}