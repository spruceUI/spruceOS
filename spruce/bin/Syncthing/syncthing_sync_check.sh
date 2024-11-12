#!/bin/ash

. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SYNCTHING_CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-/mnt/SDCARD/spruce/bin/Syncthing/config}"
API_ENDPOINT="http://localhost:8384/rest"
CONFIG_XML="$SYNCTHING_CONFIG_DIR/config.xml"
CHECK_INTERVAL=2  # Interval in seconds to wait while Syncthing is syncing
MAX_API_RETRIES=15 # Give up after this many times waiting for Syncthing API to be available
API_RETRY_INTERVAL=1 # Interval in seconds
API_KEY=""
BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
# Function to start network interface
start_network() {
    log_message "SyncthingCheck: Starting network interface..."
    ifconfig lo up
}

wait_for_syncthing_api() {
    log_message "SyncthingCheck: Waiting for Syncthing API to become available..."
    for i in $(seq 1 $MAX_API_RETRIES); do
        if curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/status" | grep -q "200"; then
            log_message "SyncthingCheck: Syncthing API is now available"
            return 0
        fi
        sleep $API_RETRY_INTERVAL
    done
    log_message "SyncthingCheck: Syncthing API did not become available within the expected time"
    return 1
}

get_folders() {
    local folders=$(curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/config/folders" | jq -r '.[] | "\(.id)|\(.label)"')
    if [ -z "$folders" ]; then
        log_message "SyncthingCheck: No folders configured"
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

stop_network() {
    log_message "SyncthingCheck: Stopping network interface..."
    ifconfig lo down
}

get_devices() {
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/connections" | jq -r '.connections | keys[]'
}

are_devices_online() {
    local connected_devices=$(curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/system/connections" | jq -r '.connections | to_entries[] | select(.value.connected == true) | .key')
    if [ -n "$connected_devices" ]; then
        return 0
    else
        return 1
    fi
}

get_folder_status() {
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/db/status?folder=$1"
}

get_device_name() {
    local device_id="$1"
    curl -s -H "X-API-Key: $API_KEY" "$API_ENDPOINT/config/devices" | jq -r ".[] | select(.deviceID == \"$device_id\") | .name"
}

calculate_folder_completion() {
    local folder_id="$1"
    local folder_status=$(get_folder_status "$folder_id")
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
            *"$B_START"* | *"$B_START_2"*)
                log_message "SyncthingCheck: START button pressed - cancelling sync"
                echo "cancelled" > /tmp/sync_cancelled
                exit 0
                ;;
        esac
    done
}

monitor_sync_status() {
    local mode="$1"
    local folders=$(get_folders)
    local devices=$(get_devices)

    # Check if there are any folders configured
    if [ $? -ne 0 ] || [ -z "$folders" ]; then
        log_message "SyncthingCheck: No folders are configured. Exiting sync check."
        display -t "Syncthing Check:
No folders configured" -i "$BG_TREE"
        sleep 1
        return 1
    fi

    rm -f /tmp/sync_cancelled

    log_message "SyncthingCheck: Monitoring sync status in $mode mode"
    display -t "Syncthing Check:
Press START to cancel" -i "$BG_TREE"

    monitor_start_button &

    if [ "$mode" = "shutdown" ]; then
        force_rescan
        sleep 2
    fi

    # Always force rediscovery in case service was not running
    force_rediscovery

    # Give a few seconds for forced discovery to trigger a rescan
    sleep 5

    if ! are_devices_online; then
        log_message "SyncthingCheck: No devices found on first attempt, waiting for second attempt..."
        sleep 2
        # Second attempt
        if ! are_devices_online; then
            log_message "SyncthingCheck: No devices are online after retry. Exiting sync check."
            display -t "No devices online" -i "$BG_TREE"
            sleep 1
            return 1
        fi
    fi

    while true; do
        local all_synced=true
        local summary=""
        local status_lines=""

        if [ -f /tmp/sync_cancelled ]; then
            rm -f /tmp/sync_cancelled
            exit 1
        fi

        # Remove the status files at the beginning of each iteration
        rm -f /tmp/sync_status
        rm -f /tmp/sync_display.txt

        for device in $devices; do
            local device_name=$(get_device_name "$device")
            local short_id=$(echo "$device" | cut -c1-7)
            log_message "SyncthingCheck: Device $device_name ($short_id):"
            summary="${summary}Device $device_name ($short_id):\n"

            echo "$folders" | while IFS='|' read -r folder_id folder_label; do
                # On Startup, we only care about downloading remote files to local device
                if [ "$mode" = "startup" ]; then
                    local completion=$(calculate_folder_completion "$folder_id")
                    [ "$completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                # On Shutdown, we only care about making sure we are done uploading local files to remote device
                elif [ "$mode" = "shutdown" ]; then
                    local completion=$(calculate_total_completion "$device" "$folder_id")
                    [ "$completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                # This we display both startup/shutdown functionality, used for testing
                elif [ "$mode" = "monitor" ]; then
                    local download_completion=$(calculate_folder_completion "$folder_id")
                    local upload_completion=$(calculate_total_completion "$device" "$folder_id")
                    completion="${download_completion}/${upload_completion}"
                    [ "$download_completion" != "100" ] || [ "$upload_completion" != "100" ] && echo "not_synced" > /tmp/sync_status
                fi

                status_line="$folder_label:\n$completion%"
                log_message "SyncthingCheck:   $status_line"
                summary="${summary}  $status_line\n"

                # Append the status line to the display file with an extra blank line
                echo "$folder_label:" >> /tmp/sync_display.txt
                echo "$completion%" >> /tmp/sync_display.txt
                echo "" >> /tmp/sync_display.txt
            done
            summary="${summary}\n"
            log_message "SyncthingCheck: "
        done

        # Read the contents of the display file for display
        status_content=$(cat /tmp/sync_display.txt)
        display -t "$status_content
Press START to cancel" -i "$BG_TREE"

        if [ ! -f /tmp/sync_status ]; then
            log_message "SyncthingCheck: All folders on all devices are in sync."
            if [ "$mode" != "monitor" ]; then
                return 0
            fi
        fi

        log_message "SyncthingCheck: ---"
        sleep $CHECK_INTERVAL
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

# Main script
main() {
    start_network
    
    # Set the API key
    if ! set_api_key; then
        display -t "Error: Unable to find API key" -i "$BG_TREE"
        sleep 2
        stop_network
        exit 1
    fi

    case "$1" in
        # This mode is only used for testing, this performs both startup/shutdown at once without exiting
        --monitor)
            monitor_sync_status "monitor"
            ;;
        --startup)
            if wait_for_syncthing_api; then
                monitor_sync_status "startup"
            else
                display -t "Failed to connect to Syncthing API" -i "$BG_TREE"
                sleep 1
            fi
            ;;
        --shutdown)
            # Kill MainUI and principal so it doesn't clash with my display
            killall -9 MainUI
            killall -9 principal.sh

            if wait_for_syncthing_api; then
                monitor_sync_status "shutdown"
            else
                display -t "Failed to connect to Syncthing API" -i "$BG_TREE"
                sleep 1
            fi

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

# Call the main function
main "$@"
