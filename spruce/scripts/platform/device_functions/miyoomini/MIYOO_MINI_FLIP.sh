#!/bin/sh
# Miyoo Mini Flip: what only this model does. Sourced last by MiyooMini.sh.

mini_reenable_buttons() {
    [ -e "$BUTTON_ENABLE_FILE" ] && echo "Y" > "$BUTTON_ENABLE_FILE" 2>/dev/null # re-enable input
}

# Opted in after the 2026-10-21 live check: without the pin RetroArch's menu left 1200 MHz, with it 1400 held
pin_ra_cpuclock() {
    printf '%s\n%s\n' "$(mode_clock_mhz "$MODE")" "$RA_CPUCLOCK_MARK" > "$RA_CPUCLOCK_FILE"
}
