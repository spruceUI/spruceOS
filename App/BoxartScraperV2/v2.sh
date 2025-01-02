#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BoxartScraperV2/functions.sh

log "Starting up Boxart Scraper V2"

# Directories and files
status_img_dir="/mnt/SDCARD/App/BoxartScraper/Imgs"
messages_file="/var/log/messages"
system_config_file="/config/system.json"
roms_dir="/mnt/SDCARD/Roms"

display_image "generic"

display -t "You are about to begin box art scraping. This process can take a while. Press A to begin. Press B at any time to stop."
acknowledge

display -t "Do you want to preview boxart as it is scraped? Press A for yes, B for no." --confirm
preview=true
if confirm; then
    log "Previewing boxart as it is scraped."
    preview=true
else
    log "Not previewing boxart as it is scraped."
    preview=false
fi

# Check for Wi-Fi
wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$system_config_file")
if [ "$wifi_enabled" -eq 0 ]; then
     log_message "BoxartScraper: No active network connection, exiting."
     display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "No active network connection detected, exiting..."
     sleep 3
     exit
fi

display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "Checking network connection..."

# Make sure scrapping api is up
if [ ! ping -c 3 api.screenscraper.fr > /dev/null 2>&1 ]; then
    log_message "BoxartScraper: API not responding, exiting."
    display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "Scrapping API not responding, exiting..."
    sleep 3
    exit
fi

# Set CPU governor to performance mode
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

log "Wifi and API ready, starting. Checking $roms_dir"

for sys_dir in "$roms_dir"/*/; do
	log "Looking for roms in $rom_dir"
    if [ ! -d "$sys_dir" ]; then
        continue
    fi

    sys_name="$(basename "$sys_dir")"
    log "Found system $sys_name"

    get_ra_alias "$sys_name"
    if [ -z "$ra_name" ]; then
        #echo "BoxartScraper: Remote system name not found, skipping $sys_name"
        log "Remote system name not found, skipping $sys_name"
        continue
    fi

    get_extensions "$sys_name"
    get_system_id "$sys_name"
    get_identify_method "$sys_name"

    display_image $sys_name "Finding images for $ra_name"

    if [[ $system_id -eq 0 ]]; then
	    log "system $sys_name has no id"
	    continue
    fi

    if [ -z "$extensions" ]; then
        log "No supported extensions found for directory $sys_name, skipping"
        continue
    fi

    # get file count the terrible way
    file_count=0
    for file in "$sys_dir"*; do
	    let file_count=file_count+1
    done
    
    files_done=0
    for file in "$sys_dir"*; do
        let files_done=files_done+1
        # Check if the user pressed B to exit
        if tail -n1 "$messages_file" | grep -q "key 1 29"; then
            log "User pressed B, exiting."
            display -t "Exiting Scrapper" -d 3
            echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	        display_kill()
            exit
        fi

        rom_file_name="$(basename "$file")"

        if [ -d "$file" ] || [ "$rom_file_name" = ".*" ] \
        || ! echo "$rom_file_name" | grep -qE "\.($(echo "$extensions" | sed -e "s/ /\|/g"))$"; then
            echo "I'm out!"
            continue
        fi

        rom_name="${rom_file_name%.*}"
        image_path="${sys_dir}Imgs/$rom_name.png"

         mkdir -p "${sys_dir}Imgs"

        if [ -f "$image_path" ]; then
            skip_count=$((skip_count + 1))
            continue
        fi

        encoded_rom=$(printf '%s' "$rom_name" | sed 's/ /%20/g;s/&/%26/g;s/?/%3F/g;s/=/%3D/g')

        # use identify_method to key off the cache of images
        identify_string=""
        log "Identifying $rom_file_name with $identify_method"
        if [[ "$identify_method" == "crc" ]]; then
            # generate crc of rom
            log "Calculating CRC of ROM $file"
            identify_string=$(cat "$file" | gzip -1 -c | tail -c8 | hexdump -n4 -e '"%08X"')
        else
            log "Using ROM file name $file"
            identify_string=$encoded_rom
        fi

        # if we have a cached image url, use it
        image_url=""
        if [ -f "cache/${sys_dir}/$identify_string.url" ]; then
            image_url=$(cat "cache/${sys_dir}/$identify_string.url")
            log "using cached image url $image_url"
        else
            log "no cached image url found for $rom_file_name $rom_crc"

            api_url="https://api.screenscraper.fr/api2/jeuInfos.php?devid=njgreb&devpassword=QvhIs0D4MIy&softname=BoxartScraperV2&output=json&ssid=test&sspassword=test&systemeid=$system_id&romtype=rom&$identify_method=$identify_string"
            log "calling $api_url"
            api_response=$(curl -k "$api_url")

            if [ $? -ne 0 ]; then
                log "failed to call api for $rom_file_name $rom_crc"
                log "$api_response"
                display -t "Failed to load $rom_file_name"
                continue
            fi

            image_url=$(curl -k "$api_url" | jq -r 'first(.response.jeu.medias[] | select(.type == "box-2D" and .region == "us")).url')

            # TODO eval if file is 0 bytes and delete it

            # cache the image url via crc
            mkdir -p cache/$sys_dir
            echo "$image_url" > "cache/${sys_dir}/$identify_string.url"
        fi

        log "downloading $image_url"
        curl -k "$image_url" > "$image_path"
        if $preview; then
            display -i "$image_path" -t "Processed: $files_done / $file_count" -is 0.8 -p 0
        else
            display -t "Processed: $files_done / $file_count"
        fi
        
    done

done

# Reset CPU governor to ondemand mode
echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

display -t "Boxart scraping complete. Press A to exit."
acknowledge

display_kill()

auto_regen_tmp_update
