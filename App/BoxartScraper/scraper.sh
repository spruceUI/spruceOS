#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

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
        ARCADE)              ra_name="MAME" ;;
        ARDUBOY)             ra_name="Arduboy Inc - Arduboy" ;;
        CHAI)                ra_name="ChaiLove" ;;
        COLECO)              ra_name="Coleco - ColecoVision" ;;
        COMMODORE)           ra_name="Commodore - 64" ;;
        CPC)                 ra_name="Amstrad - CPC" ;;
        DC)                  ra_name="Sega - Dreamcast" ;;
        DOOM)                ra_name="DOOM" ;;
        DOS)                 ra_name="DOS" ;;
        FAIRCHILD)           ra_name="Fairchild - Channel F" ;;
        FBNEO)               ra_name="FBNeo - Arcade Games" ;;
        FC)                  ra_name="Nintendo - Nintendo Entertainment System" ;;
        FDS)                 ra_name="Nintendo - Family Computer Disk System" ;;
        FIFTYTWOHUNDRED)     ra_name="Atari - 5200" ;;
        GB)                  ra_name="Nintendo - Game Boy" ;;
        GBA)                 ra_name="Nintendo - Game Boy Advance" ;;
        GBC)                 ra_name="Nintendo - Game Boy Color" ;;
        GG)                  ra_name="Sega - Game Gear" ;;
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
        SCUMMVM)             ra_name="ScummVM" ;;
        SEGACD)              ra_name="Sega - Mega-CD - Sega CD" ;;
        SEGASGONE)           ra_name="Sega SG-1000" ;;
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

get_extensions() {
    case $1 in
        AMIGA)              extensions="adf adz dms fdi ipf hdf hdz lha slave info cue ccd nrg mds iso chd uae m3u zip 7z rp9" ;;
        ARCADE)             extensions="zip" ;;
        ARDUBOY)            extensions="hex" ;;
        ATARI)              extensions="a26 bin zip 7z" ;;
        CHAI)               extensions="chailove" ;;
        COLECO)             extensions="rom ri mx1 mx2 col dsk cas sg sc m3u zip 7z" ;;
        COMMODORE)          extensions="d64 zip 7z t64 crt prg nib tap" ;;
        CPC)                extensions="sna dsk kcr bin zip 7z" ;;
        CPS1|CPS2|CPS3)     extensions="zip 7z cue" ;;
        DC)                 extensions="cdi gdi cue iso chd" ;;
        DOOM)               extensions="zip wad exe" ;;
        DOS)                extensions="zip dosz exe com bat iso ins img ima vhd jrc tc m3u m3u8 conf" ;;
        EASYRPG)            extensions="zip ldb easyrpg" ;;
        FAIRCHILD)          extensions="bin rom chf zip" ;;
        FAKE08)             extensions="p8" ;;
        FBNEO)              extensions="zip" ;;
        FC|FDS)             extensions="fds nes unif unf zip 7z" ;;
        FFPLAY)             extensions="mp4 mp3" ;;
        FIFTYTWOHUNDRED)    extensions="a52 zip 7z bin" ;;
        GB|GBC)             extensions="bin dmg gb gbc zip 7z" ;;
        GBA)                extensions="bin gba zip 7z" ;;
        GG)                 extensions="bin gg zip 7z" ;;
        GW)                 extensions="mgw zip 7z" ;;
        INTELLIVISION)      extensions="bin int zip 7z" ;;
        LYNX)               extensions="lnx zip" ;;
        MAME2003PLUS)       extensions="zip" ;;
        MD|MS|MSUMD)        extensions="gen smd md 32x bin iso sms 68k chd zip 7z" ;;
        MSU1)               extensions="sfc smc bml xml bs" ;;
        MSX)                extensions="rom mx1 mx2 dsk cas zip 7z m3u" ;;
        N64)                extensions="n64 v64 z64 bin usa pal jap zip 7z" ;;
        NDS)                extensions="nds zip 7z rar" ;;
        NEOCD)              extensions="cue chd m3u" ;;
        NEOGEO)             extensions="zip 7z" ;;
        NGP|NGPC)           extensions="ngp ngc zip 7z" ;;
        OPENBOR)            extensions="pak" ;;
        ODYSSEY)            extensions="bin zip 7z" ;;
        PCE|PCECD)          extensions="pce ccd iso img chd cue zip 7z" ;;
        PICO8)              extensions="p8 png p8.png" ;;
        POKE)               extensions="min zip" ;;
        PORTS)              extensions="zip sh" ;;
        PS)                 extensions="bin cue img mdf pbp PBP toc cbn m3u chd" ;;
        PSP)                extensions="iso cso" ;;
        QUAKE)              extensions="fbl pak" ;;
        SATELLAVIEW)        extensions="bs sfc smc swc fig st zip 7z" ;;
        SCUMMVM)            extensions="scummvm" ;;
        SEGACD|SEGASGONE)   extensions="gen smd md 32x cue iso sms 68k chd m3u zip 7z" ;;
        SEVENTYEIGHTHUNDRED) extensions="a78 zip" ;;
        SFC)                extensions="smc fig sfc gd3 gd7 dx2 bsx bs swc st zip 7z" ;;
        SGB)                extensions="bin gb gbc gba zip 7z" ;;
        SGFX)               extensions="pce sgx cue ccd chd zip 7z" ;;
        SUFAMI)             extensions="smc zip 7z" ;;
        SUPERVISION)        extensions="sv bin zip 7z" ;;
        THIRTYTWOX)         extensions="gen smd md 32x bin iso sms 68k chd zip 7z" ;;
        TIC)                extensions="tic fd sap k7 m7 rom zip 7z" ;;
        VB)                 extensions="vb vboy zip 7z" ;;
        VECTREX)            extensions="vec zip 7z" ;;
        VIC20)              extensions="d64 d6z d71 d7z d80 d81 d82 d8z g64 g6z g41 g4z x64 x6z nib nbz d2m d4m t64 tap tcrt prg p00 crt bin cmd m3u vfl vsf zip 7z gz 20 40 60 a0 b0 rom" ;;
        VIDEOPAC)           extensions="bin zip 7z" ;;
        WOLF)               extensions="ecwolf exe" ;;
        WS|WSC)             extensions="ws wsc pc2 zip 7z" ;;
        X68000)             extensions="dim zip img d88 88d hdm dup 2hd xdf hdf cmd m3u 7z" ;;
        ZXS)                extensions="tzx tap z80 rzx scl trd zip 7z" ;;
        *)                  extensions='' ;;
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

# Directories and files
status_img_dir="/mnt/SDCARD/App/BoxartScraper/Imgs"
messages_file="/var/log/messages"
system_config_file="/config/system.json"
roms_dir="/mnt/SDCARD/Roms"

# Function to show splash screen
display_image() {
    local image_path="$status_img_dir/$1.png"
    if [ -f "$image_path" ]; then
        display -i "$image_path"
    else
        display -i "$status_img_dir/generic.png"
    fi
}
display_image "generic"

# Check for Wi-Fi and active connection
wifi_enabled=$(awk '/wifi/ { gsub(/[,]/,"",$2); print $2}' "$system_config_file")
if [ "$wifi_enabled" -eq 0 ] || ! ping -c 3 thumbnails.libretro.com > /dev/null 2>&1; then
    log_message "BoxartScraper: No active network connection, exiting."
	display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "No active network connection detected, exiting..."
    sleep 3
    exit
fi

# Set CPU governor to performance mode
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Process each system directory
for sys_dir in "$roms_dir"/*/; do
    if [ ! -d "$sys_dir" ]; then
        continue
    fi

    sys_name="$(basename "$sys_dir")"
    log_message "BoxartScraper: Scraping box art for $sys_name"

    # Get remote alias name
    get_ra_alias "$sys_name"
    if [ -z "$ra_name" ]; then
        log_message "BoxartScraper: Remote system name not found, skipping $sys_name"
        continue
    fi

    display_image "$sys_name"

    get_extensions "$sys_name"

    if [ -z "$extensions" ]; then
        log_message "BoxartScraper: No supported extensions found for directory $sys_name, skipping"
        continue
    fi

    skip_count=0
    scraped_count=0
    non_found_count=0

    for file in "$sys_dir"*; do
        # Check if the user pressed B to exit
        if tail -n1 "$messages_file" | grep -q "key 1 29"; then
            log_message "BoxartScraper: User pressed B, exiting."
            display_image "user_exit" -d 3
            echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
            exit
        fi

        rom_file_name="$(basename "$file")"

        # Skip directories, dot files, and non-supported files
        if [ -d "$file" ] || [ "$rom_file_name" = ".*" ] \
        || ! echo "$rom_file_name" | grep -qE "\.($(echo "$extensions" | sed -e "s/ /\|/g"))$"; then
            continue
        fi

        rom_name="${rom_file_name%.*}"
        image_path="${sys_dir}Imgs/$rom_name.png"

        # Create Imgs directory if it doesn't exist
        mkdir -p "${sys_dir}Imgs"

        if [ -f "$image_path" ]; then
            skip_count=$((skip_count + 1))
            continue
        fi

        remote_image_name=$(find_image_name "$sys_name" "$rom_file_name")

        if [ -z "$remote_image_name" ]; then
            non_found_count=$((non_found_count + 1))
            continue
        fi

        boxart_url=$(echo "http://thumbnails.libretro.com/$ra_name/Named_Boxarts/$remote_image_name" | sed 's/ /%20/g')
        log_message "BoxartScraper: Downloading $boxart_url" -v
        curl -k -s -o "$image_path" "$boxart_url" || rm -f "$image_path" # Remove image if not found

        if [ -f "$image_path" ]; then
            scraped_count=$((scraped_count + 1))
        else
            non_found_count=$((non_found_count + 1))
        fi
    done
    log_message "BoxartScraper: $sys_name: Scraped: $scraped_count, Skipped: $skip_count, Not Found: $non_found_count"
done

# Reset CPU governor to ondemand mode
echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

auto_regen_tmp_update
