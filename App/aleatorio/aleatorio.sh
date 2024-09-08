#!/bin/sh

cd "$(dirname "$1")" || exit
SIMPLIFIED_PATH=$(pwd)
CARPETA=$(basename "$SIMPLIFIED_PATH")
BASE_DIR="/mnt/SDCARD/Roms"
EMU_DIR="/mnt/SDCARD/Emu"
CONFIG_PATH=$EMU_DIR/$CARPETA
CABEZA_ESTADO=$(head -n 14 /tmp/state.json)
PLATAFORMA=$(grep '"label":' $CONFIG_PATH/config.json | sed 's/.*"label":\s*"\([^"]*\)".*/\1/')

LAST_SELECTED_FILE="/tmp/last_selected_game.txt"

get_random_number() {
    dir="/mnt/SDCARD/Roms/$CARPETA"
    file_count=$(find "$dir" -maxdepth 1 -type f ! -name "*.db" ! -name "*.xml" ! -name "*.png" | wc -l)
    if [ "$file_count" -gt 0 ]; then
        random_number=$(awk -v min=0 -v max="$file_count" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
        echo "$random_number"
    else
        echo "No hay archivos válidos en $dir"
        exit 1
    fi
}

if [ -f "$LAST_SELECTED_FILE" ]; then
    last_random_number=$(cat "$LAST_SELECTED_FILE")
else
    last_random_number=""
fi

selected_dir="$CARPETA"
if [ -n "$selected_dir" ]; then
    random_number=$(get_random_number "$selected_dir")
    while [ "$random_number" = "$last_random_number" ]; do
        random_number=$(get_random_number "$selected_dir")
    done
    echo "$random_number" > "$LAST_SELECTED_FILE"
else
    echo "No se encontraron directorios válidos con archivos dentro."
fi

echo $CABEZA_ESTADO > /tmp/state.json
randomascinco=$random_number
randomascinco=$((randomascinco +5))
echo ' "title": -1, "type": 5, "currpos": '$random_number', "pagestart": '$random_number', "pageend": '$randomascinco', "emuname": "'$PLATAFORMA'" }] }' >> /tmp/state.json

