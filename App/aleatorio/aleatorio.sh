#!/bin/sh
# Cambia temporalmente al directorio y obtén la ruta completa
cd "$(dirname "$1")" || exit
SIMPLIFIED_PATH=$(pwd)
# Extraer el último directorio de la ruta
CARPETA=$(basename "$SIMPLIFIED_PATH")
# Ruta base donde están los directorios de ROMs
BASE_DIR="/mnt/SDCARD/Roms"
EMU_DIR="/mnt/SDCARD/Emu"
CONFIG_PATH=$EMU_DIR/$CARPETA
CABEZA_ESTADO=$(head -n 14 /tmp/state.json)
PLATAFORMA=$(grep '"label":' $CONFIG_PATH/config.json | sed 's/.*"label":\s*"\([^"]*\)".*/\1/')
# Función para obtener un número aleatorio basado en la cantidad de archivos válidos
get_random_number() {
    dir="/mnt/SDCARD/Roms/$CARPETA"
    # Contar solo archivos en el directorio principal sin subdirectorios
    file_count=$(find "$dir" -maxdepth 1 -type f ! -name "*.db" ! -name "*.xml" ! -name "*.png" | wc -l)
    if [ "$file_count" -gt 0 ]; then
        random_number=$(awk -v min=0 -v max="$file_count" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
        echo "$random_number"
    else
        echo "No hay archivos válidos en $dir"
        exit 1
    fi
}

selected_dir="$CARPETA"
# Verificar si se ha encontrado un directorio válido
if [ -n "$selected_dir" ]; then
    echo "Directorio seleccionado: $selected_dir"
    # Obtener un número aleatorio basado en el número de archivos
    random_number=$(get_random_number "$selected_dir")

    if [ -n "$random_number" ]; then
        echo "Número aleatorio: $random_number"
    fi
else
    echo "No se encontraron directorios válidos con archivos dentro."
fi

echo $CABEZA_ESTADO > /tmp/state.json
randomascinco=$random_number
randomascinco=$((randomascinco +5))
echo ' "title": -1, "type": 5, "currpos": '$random_number', "pagestart": '$random_number', "pageend": '$randomascinco', "emuname": "'$PLATAFORMA'" }] }' >> /tmp/state.json
