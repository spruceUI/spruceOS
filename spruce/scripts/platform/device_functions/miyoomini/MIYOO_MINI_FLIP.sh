#!/bin/sh
# Miyoo Mini Flip: what only this model does. Sourced last by MiyooMini.sh.

mini_reenable_buttons() {
    [ -e "$BUTTON_ENABLE_FILE" ] && echo "Y" > "$BUTTON_ENABLE_FILE" 2>/dev/null # re-enable input
}
