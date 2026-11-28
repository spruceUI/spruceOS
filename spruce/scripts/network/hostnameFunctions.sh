#!/bin/sh

# Device hostname resolution. Callers must already have sourced helperFunctions.sh
# (PLATFORM, PLATFORM_FAMILY, MINI_MODEL, BASEOS_TARGET).

HOSTNAME_STATE_FILE="${HOSTNAME_STATE_FILE:-/tmp/spruce_hostname}"
MAGICX_DEVICE_FILE="${MAGICX_DEVICE_FILE:-/usr/magicx/device}"
DEVICE_HOSTNAME_FILE="${DEVICE_HOSTNAME_FILE:-/tmp/spruce_device_hostname}"
KERNEL_HOSTNAME_FILE="${KERNEL_HOSTNAME_FILE:-/proc/sys/kernel/hostname}"

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

# The firmware's own hostname, captured once per boot (by the first get_spruce_hostname call,
# whatever the source, which precedes device_set_hostname) so later calls still see it after
# spruce has changed the kernel name.
get_device_hostname() {
    if [ -s "$DEVICE_HOSTNAME_FILE" ]; then
        head -n 1 "$DEVICE_HOSTNAME_FILE"
        return
    fi
    _device_name="$(normalize_hostname "$(head -n 1 "$KERNEL_HOSTNAME_FILE" 2>/dev/null)")"
    case "$_device_name" in
        "" | none | localhost | localhost-localdomain) _device_name="$(get_model_hostname)" ;;
    esac
    echo "$_device_name" >"$DEVICE_HOSTNAME_FILE" 2>/dev/null
    echo "$_device_name"
}

# Device name setting: Device (the firmware's name, the default), spruce (the model name) or
# Custom (the typed name, the model name while empty).
get_spruce_hostname() {
    get_device_hostname >/dev/null
    case "$(get_config_value '.menuOptions."Network Settings".hostnameSource.selected' "")" in
        spruce) get_model_hostname ;;
        Custom)
            _user_name="$(normalize_hostname "$(get_config_value '.menuOptions."Network Settings".hostname.selected' "")")"
            if [ -n "$_user_name" ]; then
                echo "$_user_name"
            else
                get_model_hostname
            fi
            ;;
        *) get_device_hostname ;;
    esac
}
