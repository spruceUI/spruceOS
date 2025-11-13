#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg


(
    /mnt/SDCARD/App/PyUI/launch.sh -buttonListenerMode True | while read -r line; do
        case "$line" in
            *"KEY,ControllerInput.MENU,PRESS"*)
                touch /tmp/kill_scraper
                ;;
        esac
    done
) &


# ==========================================================
# Box Art Scraper Script
# ==========================================================
# This script scrapes box art for various gaming systems.
# It reads system configurations and fetches appropriate
# box art images, while handling various scenarios and errors.
# ==========================================================
# Function to get the Remote Alias (RA) name for a given system
get_ra_alias() {
    case $1 in
        AMIGA)               ra_name="Commodore - Amiga" ;;
        ATARI)               ra_name="Atari - 2600" ;;
        ATARIST)             ra_name="Atari - ST" ;;
        ARCADE|CPS1|CPS2|CPS3)    ra_name="MAME" ;;
        ARDUBOY)             ra_name="Arduboy Inc - Arduboy" ;;
        CHAI)                ra_name="ChaiLove" ;;
        COLECO)              ra_name="Coleco - ColecoVision" ;;
        COMMODORE)           ra_name="Commodore - 64" ;;
        CPC)                 ra_name="Amstrad - CPC" ;;
        DC)                  ra_name="Sega - Dreamcast" ;;
        DOOM)                ra_name="DOOM" ;;
        DOS)                 ra_name="DOS" ;;
        EIGHTHUNDRED)        ra_name="Atari - 8-bit" ;;
        FAIRCHILD)           ra_name="Fairchild - Channel F" ;;
        FBNEO)               ra_name="FBNeo - Arcade Games" ;;
        FC)                  ra_name="Nintendo - Nintendo Entertainment System" ;;
        FDS)                 ra_name="Nintendo - Family Computer Disk System" ;;
        FIFTYTWOHUNDRED)     ra_name="Atari - 5200" ;;
        GB)                  ra_name="Nintendo - Game Boy" ;;
        GBA)                 ra_name="Nintendo - Game Boy Advance" ;;
        GBC)                 ra_name="Nintendo - Game Boy Color" ;;
        GG)                  ra_name="Sega - Game Gear" ;;
        GW)                  ra_name="Handheld Electronic Game" ;;
        INTELLIVISION)       ra_name="Mattel - Intellivision" ;;
        LYNX)                ra_name="Atari - Lynx" ;;
        MD)                  ra_name="Sega - Mega Drive - Genesis" ;;
        MS)                  ra_name="Sega - Master System - Mark III" ;;
        MSU1)                ra_name="Nintendo - Super Nintendo Entertainment System" ;;
        MSUMD)               ra_name="Sega - Mega Drive - Genesis" ;;
        MSX)                 ra_name="Microsoft - MSX" ;;
        N64)                 ra_name="Nintendo - Nintendo 64" ;;
        NDS)                 ra_name="Nintendo - Nintendo DS" ;;
        NEOCD)               ra_name="SNK - Neo Geo CD" ;;
        NEOGEO)              ra_name="SNK - Neo Geo" ;;
        NGP)                 ra_name="SNK - Neo Geo Pocket" ;;
        NGPC)                ra_name="SNK - Neo Geo Pocket Color" ;;
        ODYSSEY)             ra_name="Magnavox - Odyssey2" ;;
        PCE)                 ra_name="NEC - PC Engine - TurboGrafx 16" ;;
        PCECD)               ra_name="NEC - PC Engine CD - TurboGrafx-CD" ;;
        POKE)                ra_name="Nintendo - Pokemon Mini" ;;
        PS)                  ra_name="Sony - PlayStation" ;;
        PSP)                 ra_name="Sony - PlayStation Portable" ;;
        QUAKE)               ra_name="Quake" ;;
        SATELLAVIEW)         ra_name="Nintendo - Satellaview" ;;
        SATURN)              ra_name="Sega - Saturn" ;; # todo: handle saturn mask on A30
        SCUMMVM)             ra_name="ScummVM" ;;
        SEGACD)              ra_name="Sega - Mega-CD - Sega CD" ;;
        SEGASGONE)           ra_name="Sega - SG-1000" ;;
        SEVENTYEIGHTHUNDRED) ra_name="Atari - 7800" ;;
        SFC)                 ra_name="Nintendo - Super Nintendo Entertainment System" ;;
        SGB)                 ra_name="Nintendo - Game Boy" ;;
        SGFX)                ra_name="NEC - PC Engine SuperGrafx" ;;
        SUFAMI)              ra_name="Nintendo - Sufami Turbo" ;;
        SUPERVISION)         ra_name="Watara - Supervision" ;;
        THIRTYTWOX)          ra_name="Sega - 32X" ;;
        TIC)                 ra_name="TIC-80" ;;
        VB)                  ra_name="Nintendo - Virtual Boy" ;;
        VECTREX)             ra_name="GCE - Vectrex" ;;
        VIC20)               ra_name="Commodore - VIC-20" ;;
        VIDEOPAC)            ra_name="Philips - Videopac+" ;;
        WOLF)                ra_name="Wolfenstein 3D" ;;
        WS)                  ra_name="Bandai - WonderSwan" ;;
        WSC)                 ra_name="Bandai - WonderSwan Color" ;;
        X68000)              ra_name="Sharp - X68000" ;;
        ZXS)                 ra_name="Sinclair - ZX Spectrum" ;;
        *) ra_name='' ;;
    esac
}

find_image_name() {
    local sys_name="$1"
    local rom_file_name="$2"
    local rom_without_ext

    if echo "$sys_name" | grep -qE "(ARCADE|MAME2003PLUS|NEOGEO|CPS1|CPS2|CPS3)"; then
        # These systems' roms in LibRetro are stored by their long-form name, 
        # which is kept in the miyoogamelist.xml file
        rom_without_ext=$(grep -A 2 "<path>./$rom_file_name</path>" "$roms_dir/.gamelists/$sys_name/miyoogamelist.xml" \
        | grep '<name>' | sed -e 's/<name>\(.*\)<\/name>/\1/' -e 's/^[[:blank:]]*//g')

        if [ -z "$rom_without_ext" ]; then
            rom_without_ext="${rom_file_name%.*}"
        fi
    else
        rom_without_ext="${rom_file_name%.*}"
    fi

    local image_list_file="db/${sys_name}_games.txt"

    # Check if the game list file exists
    if [ ! -f "$image_list_file" ]; then
        return
    fi

    # Try an exact match first, escaping brackets for grep
    bracket_escaped_name=$(echo "$rom_without_ext" | sed 's/\[/\\\[/g; s/\]/\\\]/g')
    image_name=$(grep -i "^$bracket_escaped_name\.png$" "$image_list_file")
    if [ -n "$image_name" ]; then
        echo "$image_name"
        return
    fi

    # Fuzzy match: remove anything in brackets, flip ampersands to underscores (libretro quirk), remove trailing whitespace
    search_term=$(echo "$rom_without_ext" | sed -e 's/&/_/g' -e 's/\[.*\]//g' -e 's/[[:blank:]]*$//g')
    matches=$(grep -E "^$search_term( \(|\.)" "$image_list_file") 

      if [ -n "$matches" ]; then
        echo "$matches" | head -1
        return
    fi

    # As a final check, try without the region or anything in parens
    search_term=$(echo "$search_term" | sed -e 's/([^)]*)//g' -e 's/[[:blank:]]*$//g')
    matches=$(grep -E "^$search_term( \(|\.)" "$image_list_file")

    if [ -n "$matches" ]; then
        # Prefer US matches, otherwise take the first match
        if echo "$matches" | grep -q '(USA)' ; then
          echo "$matches" | grep '(USA)' | head -1
        else
          echo "$matches" | head -1
        fi
    fi
}

is_wifi_connected() {
    if ping -c 3 -W 2 1.1.1.1 > /dev/null 2>&1; then
        log_message "Cloudflare ping successful; device is online."
        return 0
    else
        log_and_display_message "Cloudflare ping failed; device is offline. Aborting."
        return 1
    fi
}

# Directories and files

roms_dir="/mnt/SDCARD/Roms"

start_pyui_message_writer
log_and_display_message "Scraping box art. Please be patient, especially with large libraries! Press MENU at any time to stop scraping."
sleep 2

is_wifi_connected || exit 1

# Check if the thumbnails service is accessible, if not try to fall back to GitHub libretro-thumbnails
if ! ping -c 2 thumbnails.libretro.com > /dev/null 2>&1; then
    log_and_display_message "Libretro thumbnail service unavailable; trying fallback."
    sleep 3
    if ! ping -c 2 github.com > /dev/null 2>&1; then
        log_and_display_message "Libretro thumbnail GitHub repo is also currently unavailable. Please try again later."
        sleep 3
        exit 2
    fi
fi

start_menu_button_watchdog

# Process each system directory
for sys_dir in "$roms_dir"/*/; do
    if [ ! -d "$sys_dir" ]; then
        continue
    fi

    if [ -f /tmp/kill_scraper ]; then
        kill "$WATCHDOG_PID"
        rm -f /tmp/kill_scraper
        log_and_display_message "Stopping scraping."
        sleep 2
        exit 5
    fi

    sys_name="$(basename "$sys_dir")"

    # Get remote alias name
    get_ra_alias "$sys_name"
    if [ -z "$ra_name" ]; then
        log_message "BoxartScraper: Remote system name not found - skipping $sys_name."
        continue
    fi

    extensions="$(jq -r '.extlist' "/mnt/SDCARD/Emu/$sys_name/config.json" | awk '{gsub(/\|/, " "); print $0}')"
    games="$(find "$sys_dir" -maxdepth 2 -type f -regex ".*\.\($(echo "$extensions" | sed 's/ /\\\|/g')\)$")"
    amount_games="$(echo "$games" | wc -l)"
    sys_label="$(jq ".label" "/mnt/SDCARD/Emu/$sys_name/config.json")"

    if [ -z "$extensions" ]; then
        log_message "BoxartScraper: No supported extensions found for directory $sys_name - skipping."
        continue
    fi

    first_game=0

    for file in $games ; do

        if [ $first_game -eq 0 ]; then
            log_and_display_message "BoxartScraper: Scraping box art for $sys_name"
            first_game=1
        fi
        rom_file_name="$(basename "$file")"

        # Skip directories, dot files, and non-supported files
        if [ -d "$file" ] || [ "$rom_file_name" = ".*" ] \
        || ! echo "$rom_file_name" | grep -qE "\.($(echo "$extensions" | sed -e "s/ /\|/g"))$"; then
            continue
        fi

        # Create Imgs directory if it doesn't exist
        mkdir -p "${sys_dir}Imgs"

        rom_name="${rom_file_name%.*}"
        image_path="${sys_dir}Imgs/$rom_name.png"

        if find "${sys_dir}Imgs" -maxdepth 1 -type f -name "$rom_name.*" | grep -q .; then
            continue
        fi
        
        remote_image_name=$(find_image_name "$sys_name" "$rom_file_name")

        if [ -z "$remote_image_name" ]; then
            continue
        fi

        log_and_display_message "System: $sys_label - Scraping boxart for $rom_name."

        boxart_url=$(echo "http://thumbnails.libretro.com/$ra_name/Named_Boxarts/$remote_image_name" | sed 's/ /%20/g')
        fallback_url=$(echo "https://raw.githubusercontent.com/libretro-thumbnails/$(echo "$ra_name" | sed 's/ /_/g')/master/Named_Boxarts/$remote_image_name" | sed 's/ /%20/g') 
        log_message "BoxartScraper: Downloading $boxart_url" -v
        if ! wget -q -O "$image_path" "$boxart_url"; then
            log_message "BoxartScraper: failed to scrape $boxart_url, falling back to libretro thumbnails GitHub repo."
            rm -f "$image_path"
            if ! wget -q -O "$image_path" "$fallback_url"; then
                log_message "BoxartScraper: failed to scrape $fallback_url."
                rm -f "$image_path"
            fi
        fi

        if [ -f /tmp/kill_scraper ]; then
            kill "$WATCHDOG_PID"
            rm -f /tmp/kill_scraper
            log_and_display_message "Stopping scraping."
            sleep 2
            exit 5
        fi

    done
done

kill "$WATCHDOG_PID"
rm -f /tmp/kill_scraper

log_and_display_message "Scraping complete!"
sleep 2

stop_pyui_message_writer
touch /mnt/SDCARD/App/PyUI/pyui_resize_boxart_trigger



auto_regen_tmp_update
