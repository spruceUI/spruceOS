#!/bin/sh

APP_DIR=/mnt/SDCARD/App/ThemeNursery
ICON_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/App/themegallery.png"
CACHE_DIR=/mnt/SDCARD/spruce/cache/themenursery
UNPACKER=/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
ARCHIVE_DIR=/mnt/SDCARD/spruce/archives
IMAGE_CONFIRM_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayConfirmExit.png"
IMAGE_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayExit.png"
DIRECTION_PROMPTS="/mnt/SDCARD/miyoo/res/imgs/displayLeftRight.png"
PREVIEW_PACK_URL="https://raw.githubusercontent.com/spruceUI/Themes/main/Resources/theme_previews.7z"
THEME_BASE_URL="https://raw.githubusercontent.com/spruceUI/Themes/main/PackedThemes"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Create necessary directories
mkdir -p "$CACHE_DIR"
mkdir -p "$ARCHIVE_DIR"

# Add new variables for tracking seen themes
SEEN_THEMES_FILE="$CACHE_DIR/seen_themes.txt"
touch "$SEEN_THEMES_FILE"

# Modified setup_previews to handle first-time downloads
setup_previews() {
    local timestamp_file="$CACHE_DIR/last_update"
    local max_age=1200  # 20 minutes in seconds
    local current_time=$(date +%s)
    local should_update=1

    # Check if timestamp exists and is recent
    if [ -f "$timestamp_file" ]; then
        local last_update=$(cat "$timestamp_file")
        local age=$((current_time - last_update))
        if [ $age -lt $max_age ]; then
            should_update=0
        fi
    fi

    # Update previews if needed
    if [ $should_update -eq 1 ] || [ ! -d "$CACHE_DIR/previews" ] || [ -z "$(find "$CACHE_DIR/previews" -name "*.png" 2>/dev/null)" ]; then
        display --icon "$ICON_PATH" -t "Downloading theme previews..."
        rm -rf "$CACHE_DIR/previews"
        mkdir -p "$CACHE_DIR/previews"
        
        if ! curl -s -k -L -o "$CACHE_DIR/theme_previews.7z" "$PREVIEW_PACK_URL"; then
            display --icon "$ICON_PATH" -t "Failed to download theme previews!" -d 2
            exit 1
        fi
        
        if ! 7zr x "$CACHE_DIR/theme_previews.7z" -o"$CACHE_DIR/previews" 2>&1; then
            display --icon "$ICON_PATH" -t "Failed to extract theme previews!" -d 2
            log_message "Theme Nursery: 7z extraction error output: $?"
            rm -f "$CACHE_DIR/theme_previews.7z"
            exit 1
        fi
        rm -f "$CACHE_DIR/theme_previews.7z"
        
        # Update timestamp
        echo "$current_time" > "$timestamp_file"
    fi
    
    # Final check if we have any preview files
    if [ -z "$(find "$CACHE_DIR/previews" -name "*.png" 2>/dev/null)" ]; then
        display --icon "$ICON_PATH" -t "No theme previews found!" -d 2
        exit 1
    fi

    # After successful preview extraction, mark new themes
    if [ $should_update -eq 1 ]; then
        # Create temporary file of current themes
        find "$CACHE_DIR/previews" -name "*.png" -exec basename {} .png \; > "$CACHE_DIR/current_themes.txt"
        
        # Only mark new themes if this isn't first run (seen_themes file has content)
        if [ -s "$SEEN_THEMES_FILE" ]; then
            while read -r theme; do
                if ! grep -q "^${theme}$" "$SEEN_THEMES_FILE"; then
                    mv "$CACHE_DIR/previews/${theme}.png" "$CACHE_DIR/previews/${theme}.new.png"
                    echo "$theme" >> "$SEEN_THEMES_FILE"
                fi
            done < "$CACHE_DIR/current_themes.txt"
        else
            # First time run - just populate seen_themes file without marking as new
            cat "$CACHE_DIR/current_themes.txt" > "$SEEN_THEMES_FILE"
        fi
        
        rm -f "$CACHE_DIR/current_themes.txt"
    fi
}

# Modified get_theme_list to prioritize new themes
get_theme_list() {
    # First list new themes
    find "$CACHE_DIR/previews" -name "*.new.png" -exec basename {} .new.png \; | sort > "$CACHE_DIR/theme_list.txt"
    # Then list regular themes
    find "$CACHE_DIR/previews" -name "*.png" ! -name "*.new.png" -exec basename {} .png \; | sort >> "$CACHE_DIR/theme_list.txt"
    cat "$CACHE_DIR/theme_list.txt"
    rm -f "$CACHE_DIR/theme_list.txt"
}

# Modified show_theme_preview to include index with proper newlines
show_theme_preview() {
    local theme_name="$1"
    local preview_path
    local display_name="$theme_name"
    
    # Check if it's a new theme
    if [ -f "$CACHE_DIR/previews/${theme_name}.new.png" ]; then
        preview_path="$CACHE_DIR/previews/${theme_name}.new.png"
        display_name="${theme_name} - New!"
    else
        preview_path="$CACHE_DIR/previews/${theme_name}.png"
    fi
    
    # Check if theme is installed
    if [ -d "/mnt/SDCARD/Themes/${theme_name}" ]; then
        display_name="${display_name} - Installed"
    fi
    
    # Check if file exists and log details
    if [ ! -f "$preview_path" ]; then
        log_message "Theme Nursery: Preview file not found!"
        display --icon "$ICON_PATH" -t "Preview image not found!"
        return 1
    fi
    
    display_kill
    display -t "$display_name









${current_theme}/${total_themes}" -p 10 -s 30 -w 600 -a middle \
        --add-image "$preview_path" 0.73 240 middle \
        --add-image "$IMAGE_CONFIRM_EXIT" 1.0 240 middle \
        --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
}

download_theme() {
    local theme_name="$1"
    local encoded_name=$(echo "$theme_name" | sed 's/ /%20/g' | sed "s/'/%27/g")
    local theme_url="${THEME_BASE_URL}/${encoded_name}.7z"
    local temp_path="$ARCHIVE_DIR/temp_${theme_name}.7z"
    local final_path="$ARCHIVE_DIR/preMenu/${theme_name}.7z"
    
    display --icon "$ICON_PATH" -t "Downloading ${theme_name}..."
    
    # Get file size for progress tracking
    TARGET_SIZE_BYTES="$(curl -k -I -L "$theme_url" 2>/dev/null | grep -i "Content-Length" | tail -n1 | cut -d' ' -f 2)"
    TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
    TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
    
    . /mnt/SDCARD/App/-OTA/downloaderFunctions.sh
    download_progress "$temp_path" "$TARGET_SIZE_MEGA" "Now downloading ${theme_name}!" &
    download_pid=$!
    
    if ! curl -s -k -L -o "$temp_path" "$theme_url"; then
        kill $download_pid
        rm -f "$temp_path"
        display --icon "$ICON_PATH" -t "Download failed for ${theme_name}! Please try again." -o
        return 1
    fi
    kill $download_pid
    
    if [ -f "$temp_path" ]; then
        # Create preMenu directory if it doesn't exist
        mkdir -p "$ARCHIVE_DIR/preMenu"
        # Move the completed download to the final location
        mv "$temp_path" "$final_path"
        display --icon "$ICON_PATH" -t "Download complete!"
        return 0
    else
        display --icon "$ICON_PATH" -t "Download failed! Please try again." -o
        return 1
    fi
}

# Add this new function before the main loop
redownload_installed_themes() {
    # Get list of installed themes that have matching previews
    local installed_count=0
    local temp_list=""
    
    # Iterate through installed themes and check for preview existence
    for theme_dir in /mnt/SDCARD/Themes/*/; do
        [ -d "$theme_dir" ] || continue
        theme_name=$(basename "$theme_dir")
        
        # Check if preview exists (either normal or .new)
        if [ -f "$CACHE_DIR/previews/${theme_name}.png" ] || [ -f "$CACHE_DIR/previews/${theme_name}.new.png" ]; then
            temp_list="${temp_list}${theme_name}\n"
            installed_count=$((installed_count + 1))
        fi
    done
    
    if [ $installed_count -eq 0 ]; then
        display --icon "$ICON_PATH" -t "No downloadable themes installed!" -d 2
        return 1
    fi
    
    # Show confirmation dialog
    display --icon "$ICON_PATH" -t "Re-download all ${installed_count} available themes?" --confirm

    if confirm; then
        # Process each theme from our filtered list
        printf "%b" "$temp_list" | while IFS= read -r theme_name; do
            [ -z "$theme_name" ] && continue
            display --icon "$ICON_PATH" -t "Updating: ${theme_name}"
            download_theme "$theme_name"
        done
        
        # Run unpacker silently after all downloads
        sh "$UNPACKER" --silent &
        return 0
    else
        return 1
    fi
}

# Initial setup
setup_previews

# Get theme list and count
THEME_LIST=$(get_theme_list)
total_themes=$(echo "$THEME_LIST" | wc -l)
current_theme=1

# Show first theme
current_theme_name=$(echo "$THEME_LIST" | sed -n "${current_theme}p")
show_theme_preview "$current_theme_name"

# Main loop
while true; do
    action=$(get_button_press)
    log_message "Theme Garden: Button press: $action"
    case $action in
        "RIGHT")
            if [ $current_theme -lt $total_themes ]; then
                current_theme=$((current_theme + 1))
                current_theme_name=$(echo "$THEME_LIST" | sed -n "${current_theme}p")
                show_theme_preview "$current_theme_name"
            fi
            ;;
        "LEFT")
            if [ $current_theme -gt 1 ]; then
                current_theme=$((current_theme - 1))
                current_theme_name=$(echo "$THEME_LIST" | sed -n "${current_theme}p")
                show_theme_preview "$current_theme_name"
            fi
            ;;
        "A")
            current_theme_name=$(echo "$THEME_LIST" | sed -n "${current_theme}p")
            download_theme "$current_theme_name"
            sh "$UNPACKER" --silent &
            show_theme_preview "$current_theme_name"
            ;;
        "B")
            display_kill
            sh "$UNPACKER"
            flag_remove "silentUnpacker"
            exit 0
            ;;
        "START")
            redownload_installed_themes
            # After bulk update, show current theme preview again
            show_theme_preview "$current_theme_name"
            ;;
    esac
done
