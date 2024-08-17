#!/bin/sh

IMAGE_PATH="/mnt/SDCARD/icons/systemoptions/648.png"
current_dir="$(dirname "$0")"
script_path="$current_dir/launch.sh"
config_path="$current_dir/config.json"

update_cpu_config_name() {
    if [ -f "$config_path" ]; then
        sed -i 's|"name": "✓ CPU is at 648 MHz"|"name": "Set CPU to 648 MHz"|g' "$config_path"
        sed -i 's|"name": "✓ CPU is at 816 MHz"|"name": "Set CPU to 816 MHz"|g' "$config_path"
        sed -i 's|"name": "✓ CPU is at 1200 MHz"|"name": "Set CPU to 1200 MHz"|g' "$config_path"
        sed -i 's|"name": "✓ CPU is at 1344 MHz"|"name": "Set CPU to 1344 MHz"|g' "$config_path"
        sed -i 's|"name": "✓ CPU is at 1512 MHz"|"name": "Set CPU to 1512 MHz"|g' "$config_path"
        sed -i 's|"name": "Set CPU to 648 MHz"|"name": "✓ CPU is at 648 MHz"|g' "$config_path"
    fi
}

update_cpu_config_name

if command -v sed &> /dev/null; then
    sed -i 's|\(/mnt/SDCARD/App/utils/utils performance [12] \)[0-9]*|\1648|g' "$script_path"
fi

if [ -f "$IMAGE_PATH" ]; then
    show "$IMAGE_PATH" &
    show_pid=$!

    sleep 2

    kill "$show_pid"
fi