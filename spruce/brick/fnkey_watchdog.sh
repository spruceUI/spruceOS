#!/bin/sh
# Dispatch the Brick's two Fn keys by running the action the user picked in the
# "Fn Key and Switch Settings" editor.
#
# On stock firmware the TrimUI keymon daemon reads the editor's per-key mapping
# and runs the chosen action on each Fn press. spruce deliberately does not run
# keymon (it replaced keymon everywhere with its own getevent watchdogs), so the
# Fn keys did nothing. This watchdog is the spruce-native replacement for that
# one job: watch the input node, and on an Fn key-down run the mapped action.
#
# Data model (all owned by the editor, /usr/trimui/apps/fn_editor/fneditor):
#   /usr/trimui/fnkeys/f1key_launch  - one line, absolute path to the left  Fn action
#   /usr/trimui/fnkeys/f2key_launch  - one line, absolute path to the right Fn action
# The launch files are re-read on every press, so remapping in the editor takes
# effect immediately with no restart. An unmapped key has no launch file and is
# simply ignored.
#
# The action scripts are stateless togglers invoked with no argument (e.g.
# com.trimui.toggle.ledc.sh flips the LED, com.trimui.switch.backlight.sh cycles
# brightness), so this watchdog just executes the launch path as-is, exactly as
# keymon did.
#
# Key codes: on the Brick the left/right Fn keys report as $B_L3 (1 317) and
# $B_R3 (1 318) on $EVENT_PATH_READ_INPUTS_SPRUCE (event3). The Brick has no
# analog sticks, so 317/318 are exclusively the Fn keys here (the B_L3/B_R3
# naming is inherited from the shared TrimUI config). The node is read
# non-exclusively, alongside the home/buttons watchdogs that already read it.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

F1_LAUNCH="/usr/trimui/fnkeys/f1key_launch"
F2_LAUNCH="/usr/trimui/fnkeys/f2key_launch"

# Run the action named in a *key_launch file, if it points at a runnable script.
# Backgrounded so a slow action never blocks the next keypress.
run_fnkey() {
    launch_file="$1"
    which_key="$2"
    [ -r "$launch_file" ] || return 0            # key unmapped: nothing to do
    action=$(cat "$launch_file" 2>/dev/null)
    [ -n "$action" ] || return 0                 # empty mapping
    if [ ! -x "$action" ]; then
        log_message "fnkey_watchdog.sh: $which_key Fn action not executable: $action"
        return 0
    fi
    log_message "fnkey_watchdog.sh: $which_key Fn -> $action"
    "$action" &
}

log_message "fnkey_watchdog.sh: Started up."

# Outer loop restarts the reader if the getevent pipe ever exits, so the
# watchdog stays durable like its siblings. -pid $$ makes getevent exit with us.
while true; do
    getevent -pid $$ "$EVENT_PATH_READ_INPUTS_SPRUCE" | while read line; do
        case $line in
            *"key $B_L3 1"*) run_fnkey "$F1_LAUNCH" left ;;
            *"key $B_R3 1"*) run_fnkey "$F2_LAUNCH" right ;;
        esac
    done
    log_message "fnkey_watchdog.sh: getevent pipe exited, restarting..."
    sleep 1
done
