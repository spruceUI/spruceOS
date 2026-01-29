#!/bin/ash

. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SYNCTHING_CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-/mnt/SDCARD/spruce/bin/Syncthing/config}"
API_ENDPOINT="http://localhost:8384/rest"
CONFIG_XML="$SYNCTHING_CONFIG_DIR/config.xml"
API_KEY=""
SYNC_TIMEOUT="${SYNC_TIMEOUT:-600}"  # Allow override, default 10 minutes
[ "$DISPLAY_ASPECT_RATIO" = "16:9" ] && BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree.png"

check_syncthing_status() {
    if curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/status" | grep -q "200"; then
        return 0
    fi
    return 1
}

check_device_connections() {
    local connected_devices=$(curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/connections" | jq -r '.connections | to_entries[] | select(.value.connected == true) | .key')
    if [ -n "$connected_devices" ]; then
        log_message "SyncthingCheck: Devices already connected"
        return 0
    fi
    return 1
}

wait_for_syncthing_api() {
    log_message "SyncthingCheck: Checking Syncthing API availability..."
    local start_time=$(date +%s)
    local timeout=30  # Maximum wait time in seconds
    
    while true; do
        if check_syncthing_status; then
            log_message "SyncthingCheck: API is available"
            return 0
        fi
        
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            log_message "SyncthingCheck: API timeout after ${timeout}s"
            return 1
        fi
        
        sleep 1
    done
}

smart_device_discovery() {
    local max_attempts=3
    local attempt=1
    local base_timeout=5  # Start with shorter timeouts but try multiple times

    while [ $attempt -le $max_attempts ]; do
        if [ -f /tmp/sync_cancelled ]; then
            log_message "SyncthingCheck: Discovery cancelled by user"
            return 1
        fi

        if check_device_connections; then
            log_message "SyncthingCheck: Devices connected on attempt $attempt"
            return 0
        fi
        
        log_message "SyncthingCheck: No devices connected, attempt $attempt of $max_attempts..."
        force_rediscovery
        
        local timeout=$((base_timeout * attempt))  # Increase timeout with each attempt
        local start_time=$(date +%s)
        
        while true; do
            # Check for cancellation inside the timeout loop
            if [ -f /tmp/sync_cancelled ]; then
                log_message "SyncthingCheck: Discovery cancelled by user"
                return 1
            fi

            if check_device_connections; then
                log_message "SyncthingCheck: Devices connected after rediscovery"
                return 0
            fi
            
            if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
                log_message "SyncthingCheck: Timeout after ${timeout}s on attempt $attempt"
                break
            fi
            
            sleep 1
        done
        
        attempt=$((attempt + 1))
    done
    
    log_message "SyncthingCheck: Failed to connect devices after $max_attempts attempts"
    return 1
}

start_network() {
    log_message "SyncthingCheck: Starting network interface..."
    ifconfig lo up
}

stop_network() {
    log_message "SyncthingCheck: Stopping network interface..."
    ifconfig lo down
}

get_folders() {
    local folders=$(curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/config/folders" | jq -r '.[] | "\(.id)|\(.label)"')
    if [ -z "$folders" ]; then
        return 1
    fi
    echo "$folders"
}

force_rescan() {
    log_message "SyncthingCheck: Forcing rescan of all folders for upload..."
    local folders=$(get_folders)

    echo "$folders" | while IFS='|' read -r folder_id folder_label; do
        curl -s -X POST -H "X-API-Key: $API_KEY" "$API_ENDPOINT/db/scan?folder=$folder_id"
        log_message "SyncthingCheck: Initiated rescan for folder: $folder_label"
    done
}

force_rediscovery() {
    log_message "SyncthingCheck: Forcing rediscovery of devices..."
    local response=$(curl -s -X GET -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/discovery")
    if [ $? -eq 0 ]; then
        log_message "SyncthingCheck: Initiated device rediscovery"
    else
        log_message "SyncthingCheck: Error: Failed to initiate device rediscovery"
    fi
}

get_devices() {
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/connections" | jq -r '.connections | keys[]'
}

get_device_name() {
    local device_id="$1"
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/config/devices" | jq -r ".[] | select(.deviceID == \"$device_id\") | .name"
}

calculate_folder_completion() {
    local folder_id="$1"
    local folder_status=$(curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/db/status?folder=$folder_id")
    local global_bytes=$(echo "$folder_status" | jq '.globalBytes // 0')
    local need_bytes=$(echo "$folder_status" | jq '.needBytes // 0')

    if [ "$global_bytes" -eq 0 ]; then
        echo "100"
    else
        local completed_bytes=$((global_bytes - need_bytes))
        local percentage=$((completed_bytes * 100 / global_bytes))
        echo $percentage
    fi
}

get_completion() {
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/db/completion?device=$1&folder=$2"
}

calculate_total_completion() {
    local device="$1"
    local folder_id="$2"
    local completion=$(get_completion "$device" "$folder_id")

    local global_bytes=$(echo "$completion" | jq '.globalBytes // 0')
    local need_bytes=$(echo "$completion" | jq '.needBytes // 0')
    local need_deletes=$(echo "$completion" | jq '.needDeletes // 0')
    local need_items=$(echo "$completion" | jq '.needItems // 0')

    if [ "$need_deletes" -gt 0 ] || [ "$need_items" -gt 0 ] || [ "$need_bytes" -gt 0 ]; then
        local percentage=$((100 * (global_bytes - need_bytes) / global_bytes))
        echo $percentage
    else
        echo "100"
    fi
}

monitor_start_button() {
    messages_file="/var/log/messages"
    while true; do
        inotifywait "$messages_file"
        last_line=$(tail -n 1 "$messages_file")
        case $last_line in
            *"key $B_START"* | *"key $B_START_2"*)
                log_message "SyncthingCheck: START button pressed - cancelling sync"
                touch /tmp/sync_cancelled
                ;;
        esac
    done
}

monitor_sync_status() {
    local mode="$1"
    local timeout
    
    case "$mode" in
        "startup")  timeout="${STARTUP_TIMEOUT:-900}"  ;; # 15 minutes
        "shutdown") timeout="${SHUTDOWN_TIMEOUT:-900}" ;; # 15 minutes
        "monitor")  timeout="${MONITOR_TIMEOUT:-1800}"  ;; # 30 minutes
    esac
    
    local start_time=$(date +%s)
    local last_progress_time=$(date +%s)
    local previous_status=""
    local stall_timeout=120  # 2 minutes timeout for stalled sync

    local folders
    folders=$(get_folders)
    local ret=$?
    local devices
    local start_time=$(date +%s)

    # Check folders first
    if [ $ret -ne 0 ] || [ -z "$folders" ]; then
        log_message "SyncthingCheck: No folders configured. Exiting sync check."
        display -t "Syncthing Check:
No folders configured" -i "$BG_TREE"
        sleep 1
        return 1
    fi

    devices=$(get_devices)
    # Then check devices
    if [ -z "$devices" ]; then
        log_message "SyncthingCheck: No devices configured. Exiting sync check."
        display -t "Syncthing Check:
No devices configured" -i "$BG_TREE"
        sleep 1
        return 1
    fi

    rm -f /tmp/sync_cancelled
    
    log_message "SyncthingCheck: Monitoring sync status in $mode mode"
    display -t "Syncthing Check:
Press START to cancel" -i "$BG_TREE"

    # Make sure we clean up properly on any exit
    trap 'kill $monitor_pid 2>/dev/null; rm -f /tmp/sync_cancelled; log_message "SyncthingCheck: Cleanup triggered"' EXIT INT TERM

    # Start the monitor in background
    monitor_start_button &
    monitor_pid=$!

    while true; do
        # Check for manual cancellation
        if [ -f /tmp/sync_cancelled ]; then
            log_message "SyncthingCheck: Sync cancelled by user"
            display -t "Sync cancelled" -i "$BG_TREE"
            sleep 1
            return 1
        fi

        local elapsed=$(($(date +%s) - start_time))
        local stall_time=$(($(date +%s) - last_progress_time))
        
        # Check for overall timeout
        if [ $elapsed -gt $timeout ]; then
            log_message "SyncthingCheck: Sync timed out after ${timeout} seconds"
            display -t "Sync timed out after ${timeout}s" -i "$BG_TREE"
            sleep 1
            return 1
        fi

        # Check for stall timeout
        if [ $stall_time -gt $stall_timeout ]; then
            log_message "SyncthingCheck: Sync stalled - no progress for ${stall_timeout} seconds"
            display -t "Sync stalled
No progress for ${stall_timeout}s" -i "$BG_TREE"
            sleep 1
            return 1
        fi

        rm -f /tmp/sync_status
        rm -f /tmp/sync_display.txt
        current_status=""

        for device in $devices; do
            local device_name=$(get_device_name "$device")
            local short_id=$(echo "$device" | cut -c1-7)
            
            echo "$folders" | while IFS='|' read -r folder_id folder_label; do
                local status=""
                
                if [ "$mode" = "startup" ]; then
                    local completion=$(calculate_folder_completion "$folder_id")
                    [ "$completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                    status="$completion%"
                elif [ "$mode" = "shutdown" ]; then
                    local completion=$(calculate_total_completion "$device" "$folder_id")
                    [ "$completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                    status="$completion%"
                elif [ "$mode" = "monitor" ]; then
                    local download_completion=$(calculate_folder_completion "$folder_id")
                    local upload_completion=$(calculate_total_completion "$device" "$folder_id")
                    [ "$download_completion" != "100" ] || [ "$upload_completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                    status="${download_completion}/${upload_completion}%"
                fi

                current_status="${current_status}${status}"
                echo "$folder_label:" >> /tmp/sync_display.txt
                echo "$status" >> /tmp/sync_display.txt
                echo "" >> /tmp/sync_display.txt
            done
        done

        # Check if status has changed
        if [ "$current_status" != "$previous_status" ] && [ -n "$previous_status" ]; then
            last_progress_time=$(date +%s)
            log_message "SyncthingCheck: Sync progress detected, resetting stall timer"
        fi
        previous_status="$current_status"

        status_content=$(cat /tmp/sync_display.txt)
        display -t "$status_content
Press START to cancel" -i "$BG_TREE"

        if [ ! -f /tmp/sync_status ]; then
            log_message "SyncthingCheck: All folders synchronized"
            return 0
        fi

        sleep 1
    done
}

set_api_key() {
    log_message "SyncthingCheck: Reading API key from $CONFIG_XML"
    if [ ! -f "$CONFIG_XML" ]; then
        log_message "SyncthingCheck: Error: Config file $CONFIG_XML does not exist" >&2
        return 1
    fi

    API_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$CONFIG_XML")
    log_message "SyncthingCheck: API key: $API_KEY"

    if [ -z "$API_KEY" ]; then
        log_message "SyncthingCheck: Error: No API key found in config.xml" >&2
        return 1
    fi
}

main() {
    if ! set_api_key; then
        display -t "Error: Unable to find API key" -i "$BG_TREE"
        sleep 1
        exit 1
    fi

    start_network
    
    if ! check_syncthing_status; then
        log_message "SyncthingCheck: Syncthing not responsive, waiting for startup..."
        if ! wait_for_syncthing_api; then
            display -t "Failed to connect to Syncthing API" -i "$BG_TREE"
            sleep 1
            stop_network
            exit 1
        fi
    fi

    case "$1" in
        --monitor)
            monitor_sync_status "monitor"
            ;;
        --startup)
            monitor_sync_status "startup"
            ;;
        --shutdown)
            killall -9 MainUI
            killall -9 principal.sh
            monitor_sync_status "shutdown"
            killall -9 syncthing
            ;;
        *)
            log_message "SyncthingCheck: Usage: $0 {--monitor|--startup|--shutdown}"
            stop_network
            exit 1
            ;;
    esac

    exit_code=$?
    log_message "SyncthingCheck: Sync check completed with exit code: $exit_code"
    stop_network
    exit $exit_code
}

main "$@"