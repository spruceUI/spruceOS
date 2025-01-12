#!/bin/sh

# Helper function to update or create config file
update_config_file() {
    config_file="$1"
    config_data="$2"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$config_file")"
    
    # Create file if it doesn't exist
    [ ! -f "$config_file" ] && touch "$config_file"
    
    # Process each line of config data
    echo "$config_data" | while IFS= read -r line; do
        key="${line%%=*}"
        key="$(echo "$key" | sed 's/[[:space:]]*$//')"  # Trim whitespace
        
        # Remove existing line with this key if it exists
        sed -i "/${key}[[:space:]]*=/d" "$config_file"
        
        # Append new line
        echo "$line" >> "$config_file"
    done
    
    # Remove file if empty
    [ ! -s "$config_file" ] && rm "$config_file"
}

# Helper function to remove config entries
remove_config_entries() {
    config_file="$1"
    keys="$2"
    
    [ ! -f "$config_file" ] && return
    
    echo "$keys" | while IFS= read -r key; do
        key="$(echo "$key" | sed 's/[[:space:]]*$//')"  # Trim whitespace
        sed -i "/${key}[[:space:]]*=/d" "$config_file"
    done
    
    # Remove file if empty
    [ ! -s "$config_file" ] && rm "$config_file"
}