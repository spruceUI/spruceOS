#!/bin/sh
# Hold off the idle shutdown while a long job runs with no button presses
# (box art optimizing/downloading, backups, ...):
#
#   long_task.sh start    before the job
#   long_task.sh end      after it, however it ended
#
# start sets the long_task flag; idlemon_poweroffAction.sh skips while it is
# set, and idlemon simply fires again on its next check. end clears the flag
# and restarts the idle timer so the device gets a full idle period after the
# job instead of powering off the moment it finishes. principal.sh clears the
# flag every loop, so a job that crashes before "end" can't block shutdown.
# CPU/performance mode is left to the caller.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

case "$1" in
    start)
        flag_add "long_task" --tmp
        log_message "long_task.sh: started${2:+ ($2)}, idle shutdown on hold"
        ;;
    end)
        flag_remove "long_task"
        log_message "long_task.sh: ended${2:+ ($2)}, idle timer restarted"
        /mnt/SDCARD/spruce/scripts/idle_watchdog.sh > /dev/null 2>&1 &
        ;;
    *)
        echo "usage: long_task.sh start|end [name]" >&2
        exit 1
        ;;
esac
