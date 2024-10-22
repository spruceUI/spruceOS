#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/Themes/SPRUCE/Icons/App/random.png"

display --icon "$IMAGE_PATH" -t "Selecting random game - please wait a moment ;)
 
 " -p bottom
PREV_SELECTION_FILE="/mnt/SDCARD/App/RandomGame/prev_selection.txt"
PREV5_FILE="/mnt/SDCARD/App/RandomGame/5_previous.txt"

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

get_rand_folder() {
    local folder="$1"

    # count all files (except xml files) in all sub-folders
    SIZE=$(find "$folder" -mindepth 2 -maxdepth 2 -type f ! -name "*.xml" | wc -l)

    # generate random index (0 - SIZE)
    SEED=$(date +%s%N)
    RINDEX=$(awk -v max=$SIZE -v seed=$SEED 'BEGIN{srand(seed); print int(rand()*(max))}')

    # find the selected sub-folder
    for SUBFOLDER in "$folder"/*/; do

        # count all files in sub-folder
        SUBSIZE=$(find "$SUBFOLDER" -maxdepth 1 -type f ! -name "*.xml" | wc -l)

        # select sub folder if the randon index is in range  
        if [ $RINDEX -lt $SUBSIZE ]; then
        #if [ $RINDEX -eq 0 ]; then
            echo -n "$SUBFOLDER"
            return
        fi

        # adjust random index
        RINDEX=$(expr $RINDEX - $SUBSIZE)
    done
}

get_rand_file() {
    local folder="$1"
    sys_name=$(basename "$folder")
    get_extensions "$sys_name"
    OIFS="$IFS"
    IFS=$'\n'
    ALL_FILES=$(ls -d -1 "$folder"* | grep -E "\.($(echo "$extensions" | sed -e "s/ /\|/g"))$" | grep -Fxvf "$PREV5_FILE")
    SIZE=$(echo "$ALL_FILES" | wc -l)
    if [ $SIZE -gt 0 ]; then
        SEED=$(date +%s%N)
        RINDEX=$(awk -v max=$SIZE -v seed=$SEED 'BEGIN{srand(seed); print int(rand()*(max))}')
        for file in $ALL_FILES; do
            if [ $RINDEX -eq 0 ]; then
                echo -n "${file}"
                return
            fi
            RINDEX=$(expr $RINDEX - 1)
        done
    fi
    IFS="$OIFS"
}

ROM_DIR="/mnt/SDCARD/Roms"
EMU_DIR="/mnt/SDCARD/Emu"

if [ ! -d "$ROM_DIR" ] || [ ! -d "$EMU_DIR" ]; then
    exit 1
fi

NOTOK=1
while [ "$NOTOK" -eq 1 ]; do
    NOTOK=0
    SELECTED_FOLDER=$(get_rand_folder "$ROM_DIR")
    SELECTED_GAME=$(get_rand_file "$SELECTED_FOLDER")
    echo "${SELECTED_FOLDER} ${SELECTED_GAME}"
    if [ -z "$SELECTED_GAME" ]; then
        NOTOK=1
        continue
    fi
    echo "$SELECTED_GAME" >> "$PREV_SELECTION_FILE"
    tail -n 5 "$PREV_SELECTION_FILE" > "$PREV5_FILE"
    FOLDER_NAME=$(basename "$SELECTED_FOLDER")
    EMU_FOLDER="$EMU_DIR/$FOLDER_NAME"
    if [ ! -d "$EMU_FOLDER" ] || [ ! -x "$EMU_FOLDER/launch.sh" ]; then
        NOTOK=1
        continue
    fi
done

BOX_ART_PATH="$(dirname "$SELECTED_GAME")/Imgs/$(basename "$SELECTED_GAME" | sed 's/\.[^.]*$/.png/')"

if [ -f "$BOX_ART_PATH" ]; then
    display -i "$BOX_ART_PATH" -d 2
    kill $(jobs -p)
fi

cmd="\"${EMU_FOLDER}/launch.sh\" \"${SELECTED_GAME}\""
echo "$cmd" > /tmp/cmd_to_run.sh
eval "$cmd"
