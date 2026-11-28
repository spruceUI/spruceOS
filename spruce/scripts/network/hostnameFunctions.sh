#!/bin/sh

# Device hostname resolution. Callers must already have sourced helperFunctions.sh
# (PLATFORM, PLATFORM_FAMILY, MINI_MODEL, BASEOS_TARGET).

HOSTNAME_STATE_FILE="${HOSTNAME_STATE_FILE:-/tmp/spruce_hostname}"
MAGICX_DEVICE_FILE="${MAGICX_DEVICE_FILE:-/usr/magicx/device}"

# Lowercase, spaces to '-', keep [a-z0-9-], strip edge '-', truncate to 63.
normalize_hostname() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | tr ' ' '-' | tr -cd 'a-z0-9-' |
        sed 's/^-*//; s/-*$//' | cut -c1-63 | sed 's/-*$//'
}

get_model_hostname() {
    case "${PLATFORM_FAMILY:-}" in
        miyoomini)
            case "${MINI_MODEL:-}" in
                MIYOO_MINI) key="mini" ;;
                MIYOO_MINI_V4) key="miniv4" ;;
                MIYOO_MINI_PLUS) key="miniplus" ;;
                MIYOO_MINI_FLIP) key="miniflip" ;;
                *) key="${MINI_MODEL:-}" ;;
            esac
            ;;
        h700) key="${BASEOS_TARGET:-}" ;;
        oakmoss) key="$(head -n 1 "$MAGICX_DEVICE_FILE" 2>/dev/null | tr -d '\r')" ;;
        *) key="${PLATFORM:-}" ;;
    esac
    key="$(normalize_hostname "$key")"
    if [ -z "$key" ]; then
        echo "spruce"
    else
        echo "spruce-$key"
    fi
}

get_spruce_hostname() {
    get_model_hostname
}
