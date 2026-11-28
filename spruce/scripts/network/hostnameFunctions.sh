#!/bin/sh

# Device hostname resolution. Callers must already have sourced helperFunctions.sh
# (PLATFORM, PLATFORM_FAMILY, MINI_MODEL, BASEOS_TARGET).

HOSTNAME_STATE_FILE="${HOSTNAME_STATE_FILE:-/tmp/spruce_hostname}"
MAGICX_DEVICE_FILE="${MAGICX_DEVICE_FILE:-/usr/magicx/device}"
FIRMWARE_HOSTNAME_FILE="${FIRMWARE_HOSTNAME_FILE:-/tmp/spruce_firmware_hostname}"
KERNEL_HOSTNAME_FILE="${KERNEL_HOSTNAME_FILE:-/proc/sys/kernel/hostname}"

# Lowercase, spaces to '-', keep [a-z0-9-], strip edge '-', truncate to 63.
normalize_hostname() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | tr ' ' '-' | tr -cd 'a-z0-9-' |
        sed 's/^-*//; s/-*$//' | cut -c1-63 | sed 's/-*$//'
}

# The model key, e.g. flip, rgsp, miniflip; empty when detection failed.
get_model_key() {
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
    normalize_hostname "$key"
}

# Device: the model key, or spruce when there is none.
get_device_name() {
    _key="$(get_model_key)"
    echo "${_key:-spruce}"
}

# spruce: spruce-<model key>, or spruce when there is none.
get_spruce_model_hostname() {
    _key="$(get_model_key)"
    if [ -z "$_key" ]; then
        echo "spruce"
    else
        echo "spruce-$_key"
    fi
}

# The firmware's own hostname, normalised; empty when it has none. Captured once per boot (by the
# first get_spruce_hostname call, whatever the source, which precedes device_set_hostname) so later
# calls still see it after spruce has changed the kernel name. The file existing marks the capture,
# so an empty capture is not retried.
get_firmware_hostname() {
    if [ -f "$FIRMWARE_HOSTNAME_FILE" ]; then
        head -n 1 "$FIRMWARE_HOSTNAME_FILE"
        return
    fi
    _fw_name="$(normalize_hostname "$(head -n 1 "$KERNEL_HOSTNAME_FILE" 2>/dev/null)")"
    case "$_fw_name" in
        none | localhost | localhost-localdomain) _fw_name="" ;;
    esac
    echo "$_fw_name" >"$FIRMWARE_HOSTNAME_FILE" 2>/dev/null
    echo "$_fw_name"
}

# Device name setting, the name in use: device (the model name, the default), firmware (the
# firmware's name, the device name when it has none), spruce (spruce-<model>) or custom (the typed
# name, the device name while empty).
get_spruce_hostname() {
    _fw_name="$(get_firmware_hostname)"
    case "$(get_config_value '.menuOptions."Network Settings".hostnameSource.selected' "")" in
        firmware)
            if [ -n "$_fw_name" ]; then
                echo "$_fw_name"
            else
                get_device_name
            fi
            ;;
        spruce) get_spruce_model_hostname ;;
        custom)
            _user_name="$(normalize_hostname "$(get_config_value '.menuOptions."Network Settings".hostname.selected' "")")"
            if [ -n "$_user_name" ]; then
                echo "$_user_name"
            else
                get_device_name
            fi
            ;;
        *) get_device_name ;;
    esac
}
