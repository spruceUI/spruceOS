#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Settings
WIFI_INTERFACE="wlan0"
PING_TARGET="1.1.1.1"      # Use IP that is broadly available globally!
PING_COUNT=3               # Number of ping attempts
CHECK_INTERVAL=30          # Time between checks in seconds
COOLDOWN_TIME=300          # 5-minute cooldown if Wi-Fi can't reconnect
MAX_ATTEMPTS=3             # Max reconnection attempts before cooldown
ATTEMPT_WINDOW=300         # 5 minutes time window for reconnection attempts
PROCESS_NAME="MainUI"      # ONLY execute if MainUI is running!! - this will cause perf issues otherwise in emus

# Track reconnection attempts
attempt_count=0
last_attempt_time=0 
first_run=true

reset_wifi() {
    log_message "WiFi Watchdog: Resetting Wi-Fi on $WIFI_INTERFACE"
    
    # Bring the Wi-Fi interface down
    ifconfig "$WIFI_INTERFACE" down 
    killall wpa_supplicant
    killall udhcpc
    
    # Bring the Wi-Fi interface back up
    ifconfig "$WIFI_INTERFACE" up
    sleep .5
    wpa_supplicant -B -i "$WIFI_INTERFACE" -c /config/wpa_supplicant.conf
    udhcpc -i "$WIFI_INTERFACE" & 
    log_message "WiFi Watchdog: Wi-Fi reset completed."
    
    #Bring up network services
    /mnt/SDCARD/spruce/scripts/networkservices.sh &
}

# Check if Wi-Fi is up and connected
check_wifi() {
    
    # Check if the global Wi-Fi option is enabled
    wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
    
    if [ "$wifi" -eq 1 ]; then
        # Check if wlan0 is up and has an IP address
        if ! ifconfig "$WIFI_INTERFACE" | grep -q "inet "; then
            manage_reconnection
            return
        fi

        # Try to ping the external server
        if ! ping -c "$PING_COUNT" "$PING_TARGET" > /dev/null 2>&1; then
            manage_reconnection
        else
            # Reset attempt count if Wi-Fi is operational
            attempt_count=0
			
			# Check network services in the case of save/resume
			/mnt/SDCARD/spruce/scripts/networkservices.sh &
        fi
    #else
        # log_message "WiFi Watchdog: Global Wi-Fi option is disabled. Skipping Wi-Fi check."
    fi
}

# Function to handle reconnection attempts with cooldown
manage_reconnection() {
    current_time=$(date +%s)
    
    # Check if we're within the cooldown period
    if [ "$attempt_count" -ge "$MAX_ATTEMPTS" ] && [ "$(($current_time - $last_attempt_time))" -lt "$COOLDOWN_TIME" ]; then
        # log_message "WiFi Watchdog: Reached maximum reconnection attempts. Entering cooldown for $COOLDOWN_TIME seconds."
        sleep "$COOLDOWN_TIME"
        attempt_count=0 
    else
        # Reset Wi-Fi and track the attempt
        if pgrep "$PROCESS_NAME" > /dev/null; then
            reset_wifi
        fi 
        attempt_count=$((attempt_count + 1))
        last_attempt_time=$current_time
    fi
}

# Start network services on first start
if [ "$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')" -eq 1 ]; then
	/mnt/SDCARD/spruce/scripts/networkservices.sh &
fi

# Infinite loop to keep monitoring by process and Wi-Fi status
while true; do
    if pgrep "$PROCESS_NAME" > /dev/null; then
        if "$first_run"; then
		    sleep 20 # Give time for initial connection to Wifi upon boot
            first_run=false
        fi   
        check_wifi
    #else
        # log_message "WiFi Watchdog: $PROCESS_NAME is not running. Skipping Wi-Fi check."
    fi
    sleep "$CHECK_INTERVAL"
done
