# Wrapper function to log messages
log() {
    log_message "Boxart Scraper V2: $1"
}

# Wrapper function to display images (from BoxartScraper)
display_image() {
    local image_path="$status_img_dir/$1.png"
    local text=$2

    if [ -f "$image_path" ]; then
	if [ $text -eq "" ]; then
	        display -i "$image_path"
	else
		display -i "$image_path" -t "$text"
	fi
	
    else
        display -i "$status_img_dir/generic.png"
    fi
}

# Get long name of system from short name
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

# Get system ID from short name
get_system_id() {
    case $1 in
	    AMIGA)		system_id=64 ;;
	    ARCADE)		system_id=75 ;; # this is MAME, might be wrong
	    ARDUBOY) 	system_id=263 ;;
	    ATARI)		system_id=26 ;;
        FC)     	system_id=3 ;;
        SFC)    	system_id=4 ;;
        GB)     	system_id=9 ;;
    	MD)		    system_id=1 ;;
        PSP)        system_id=61 ;;
        PS)         system_id=57 ;;
        *)      	system_id=0 ;;
    esac
}

# Get rom identification method from short name
get_identify_method() {
  case $1 in
    PSP)  identify_method=romnom ;; # Name of ROM file
    PS)   identify_method=romnom ;; # Name of ROM file
    *)    identify_method=crc ;; # CRC of ROM file
  esac
}

# Get extensions for a system
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