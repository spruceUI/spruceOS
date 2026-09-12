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
# Key codes come from the platform config as FN_KEY_LEFT / FN_KEY_RIGHT, because
# the two devices with Fn keys do NOT agree on them:
#
#   Brick     317/318 (BTN_THUMBL/BTN_THUMBR) - it has no analog sticks, so those
#             codes are wired to the Fn keys and nothing else reports them
#   Brick Pro 59/60 (KEY_F1/KEY_F2) - it HAS sticks, and 317/318 are its genuine
#             stick clicks
#
# Both measured on hardware. This used to match $B_L3/$B_R3, which are 317/318 on
# both devices - correct on the Brick by luck, and on the Brick Pro would have
# fired the Fn action on every stick click.
#
# The node is read non-exclusively, alongside the home/buttons watchdogs that
# already read it.

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

if [ -z "$FN_KEY_LEFT" ] || [ -z "$FN_KEY_RIGHT" ]; then
    # An empty code would make the case pattern "key  1" match far too much.
    log_message "fnkey_watchdog.sh: FN_KEY_LEFT/FN_KEY_RIGHT unset for $PLATFORM, not starting"
    exit 0
fi

log_message "fnkey_watchdog.sh: Started up."

# Outer loop restarts the reader if the getevent pipe ever exits, so the
# watchdog stays durable like its siblings. -pid $$ makes getevent exit with us.
while true; do
    getevent -pid $$ "$EVENT_PATH_READ_INPUTS_SPRUCE" | while read line; do
        case $line in
            *"key $FN_KEY_LEFT 1"*)  run_fnkey "$F1_LAUNCH" left ;;
            *"key $FN_KEY_RIGHT 1"*) run_fnkey "$F2_LAUNCH" right ;;
        esac
    done
    log_message "fnkey_watchdog.sh: getevent pipe exited, restarting..."
    sleep 1
done
