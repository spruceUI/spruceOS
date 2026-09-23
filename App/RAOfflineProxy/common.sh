#!/bin/sh

APP_DIR=/mnt/SDCARD/App/RAOfflineProxy
APP_VERSION=v1.13.0-alpha1
APP_MAX_CACHED_GAMES=100
APP_DATA_DIR="$APP_DIR/data"
APP_PACKAGE_DIR="$APP_DIR/app"
case "$(uname -m)" in
    aarch64 | arm64) APP_LIB_DIR="$APP_DIR/lib/aarch64" ;;
    *) APP_LIB_DIR="$APP_DIR/lib/armv7" ;;
esac
APP_RETROARCH_CFG=
APP_SPRUCE_PLATFORM=
APP_SPRUCE_ZONEINFO_DIR=/mnt/SDCARD/spruce/zoneinfo
# shared-system.json is card-global; the per-device glob is older.
APP_SPRUCE_SYSTEM_JSON_GLOB='/mnt/SDCARD/Saves/spruce/shared-system.json /mnt/SDCARD/Saves/*-system.json'
RESOLVED_PYTHON_BIN=
RUNTIME_FAILURE_REASON=
RUNTIME_DETECT_LOG="$APP_DATA_DIR/runtime-detect.log"

SPRUCE_APP_ENV=/mnt/SDCARD/spruce/scripts/appEnv.sh

# spruce publishes its device name, live RetroArch config and python path here.
detect_spruce_platform() {
    if [ ! -r "$SPRUCE_APP_ENV" ]; then
        echo "RAOfflineProxy needs spruce with $SPRUCE_APP_ENV" >&2
        return 1
    fi
    . "$SPRUCE_APP_ENV"
    APP_SPRUCE_PLATFORM="$SPRUCE_PLATFORM"
}

resolve_spruce_timezone() {
    # spruce's PyUI applies the chosen zone by exporting TZ into its own environment, so
    # anything it launches inherits it. The boot hook runs from .tmp_update/updater long
    # before PyUI exists, so an autostarted proxy would otherwise stamp every award
    # timestamp in UTC.
    if [ -n "${TZ:-}" ]; then
        return 0
    fi

    if [ ! -d "$APP_SPRUCE_ZONEINFO_DIR" ]; then
        return 0
    fi

    for spruce_system_json in $APP_SPRUCE_SYSTEM_JSON_GLOB; do
        [ -r "$spruce_system_json" ] || continue

        spruce_tz="$(sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$spruce_system_json" 2>/dev/null | head -n 1)"
        [ -n "$spruce_tz" ] || continue

        spruce_zone_file="$APP_SPRUCE_ZONEINFO_DIR/$spruce_tz"
        if [ -r "$spruce_zone_file" ]; then
            # glibc reads a tz file from an absolute path when TZ starts with a colon,
            # which is exactly how spruce itself applies the setting.
            export TZ=":$spruce_zone_file"
            return 0
        fi
    done

    return 0
}

normalize_display_paths() {
    sed 's#/mnt/SDCARD/#/#g'
}

prepare_env() {
    mkdir -p "$APP_DATA_DIR"
    : > "$RUNTIME_DETECT_LOG"

    detect_spruce_platform || return 1
    resolve_spruce_timezone

    APP_RETROARCH_CFG="$SPRUCE_RA_CONFIG"

    export RAOFFLINEPROXY_CONFIG_DIR="$APP_DATA_DIR"
    export RAOFFLINEPROXY_RETROARCH_CFG="$APP_RETROARCH_CFG"
    export RAOFFLINEPROXY_APP_VERSION="${APP_VERSION#v}"
    export RAOFFLINEPROXY_CACHE_IMAGES=0
    export PYTHONPATH="$APP_PACKAGE_DIR${PYTHONPATH:+:$PYTHONPATH}"
    # glibc hands every allocating thread its own heap and grows each in 1MB chunks it
    # never returns. The proxy runs a thread per connection plus background workers, which
    # on a 103MB device cost ~15MB of arenas — about as much as the interpreter itself.
    export MALLOC_ARENA_MAX=2
    export LD_LIBRARY_PATH="$APP_LIB_DIR:/config/lib:/customer/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    [ -n "${SSL_CERT_FILE:-}" ] && export RAOFFLINEPROXY_CA_FILE="$SSL_CERT_FILE"

    return 0
}

capture_runtime_failure_reason() {
    if [ ! -s "$RUNTIME_DETECT_LOG" ]; then
        RUNTIME_FAILURE_REASON=
        return 0
    fi

    if IFS= read -r first_line < "$RUNTIME_DETECT_LOG"; then
        RUNTIME_FAILURE_REASON="$first_line"
        return 0
    fi

    RUNTIME_FAILURE_REASON=
}

# spruce ships CPython 3.10; PATH is only a fallback.
resolve_python_bin() {
    for candidate in "${SPRUCE_PYTHON:-}" "$(command -v python3 2>/dev/null)"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' \
            >/dev/null 2>"$RUNTIME_DETECT_LOG"; then
            RESOLVED_PYTHON_BIN="$candidate"
            RUNTIME_FAILURE_REASON=
            return 0
        fi
        capture_runtime_failure_reason
    done

    RESOLVED_PYTHON_BIN=
    return 1
}

run_backend() {
    python_bin="$1"
    shift
    run_backend_raw "$python_bin" "$@" | normalize_display_paths
}

run_backend_raw() {
    python_bin="$1"
    shift
    case "${1:-}" in
        boot-reconcile | start-proxy)
            # raofflineproxy.boot opens the proxy port before loading the rest
            # of the package, so an emulator started alongside this hook is not
            # refused.
            "$python_bin" -m raofflineproxy.boot "$@"
            ;;
        *)
            "$python_bin" -m raofflineproxy.main "$@"
            ;;
    esac
}

log_path() {
    printf '%s\n' "$APP_DATA_DIR/service.log"
}
