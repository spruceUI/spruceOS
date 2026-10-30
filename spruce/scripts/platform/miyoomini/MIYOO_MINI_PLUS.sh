#!/bin/sh
# Miyoo Mini Plus: what only this model does. Sourced last by MiyooMini.sh.

# Screen is off by like ~8px unless you do this, not sure why
mini_model_init() {
    cat /proc/ls
}

# Opted in after the 2026-10-21 measurement: ra32.mini re-pins this clock after its menu
pin_ra_cpuclock() {
    printf '%s\n%s\n' "$(mode_clock_mhz "$MODE")" "$RA_CPUCLOCK_MARK" > "$RA_CPUCLOCK_FILE"
}
