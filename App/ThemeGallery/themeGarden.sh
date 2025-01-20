#!/bin/sh

APP_DIR=/mnt/SDCARD/App/ThemeNursery
CACHE_DIR=/mnt/SDCARD/spruce/cache/themenursery
UNPACKER=/mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
ARCHIVE_DIR=/mnt/SDCARD/spruce/archives/preMenu
IMAGE_CONFIRM_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayConfirmExit.png"
IMAGE_EXIT="/mnt/SDCARD/miyoo/res/imgs/displayExit.png"
DIRECTION_PROMPTS="/mnt/SDCARD/miyoo/res/imgs/displayLeftRight.png"
PREVIEW_PACK_URL="https://raw.githubusercontent.com/spruceUI/Themes/main/Resources/theme_previews.7z"
THEME_BASE_URL="https://raw.githubusercontent.com/spruceUI/Themes/main/PackedThemes"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_verbose

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
        display -t "Downloading theme previews..." -p 240
        rm -rf "$CACHE_DIR/previews"
        mkdir -p "$CACHE_DIR/previews"
        
        if ! curl -s -k -L -o "$CACHE_DIR/theme_previews.7z" "$PREVIEW_PACK_URL"; then
            display -t "Failed to download theme previews!" -p 240 -d 2
            exit 1
        fi
        
        if ! 7zr x "$CACHE_DIR/theme_previews.7z" -o"$CACHE_DIR/previews" 2>&1; then
            display -t "Failed to extract theme previews!" -p 240 -d 2
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
        display -t "No theme previews found!" -p 240 -d 2
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

# Modified show_theme_preview to handle new themes
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
        display -t "Preview image not found!" -p 240
        return 1
    fi
    
    # Log file permissions and size
    ls -l "$preview_path" | log_message
    
    display_kill
    display -t "$display_name" -p 20 -s 30 -w 600 -a middle \
        --add-image "$preview_path" 0.73 240 middle \
        --add-image "$IMAGE_CONFIRM_EXIT" 1.0 240 middle \
        --add-image "$DIRECTION_PROMPTS" 1.0 240 middle
}

download_theme() {
    local theme_name="$1"
    local encoded_name=$(echo "$theme_name" | sed 's/ /%20/g' | sed "s/'/%27/g")
    local theme_url="${THEME_BASE_URL}/${encoded_name}.7z"
    local output_path="$ARCHIVE_DIR/${theme_name}.7z"
    
    display -t "Downloading ${theme_name}..." -p 240
    
    # Get file size for progress tracking
    TARGET_SIZE_BYTES="$(curl -k -I -L "$theme_url" 2>/dev/null | grep -i "Content-Length" | tail -n1 | cut -d' ' -f 2)"
    TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
    TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
    
    . /mnt/SDCARD/App/-OTA/downloaderFunctions.sh
    download_progress "$output_path" "$TARGET_SIZE_MEGA" "Now downloading ${theme_name}!" &
    download_pid=$!
    
    if ! curl -s -k -L -o "$output_path" "$theme_url"; then
        kill $download_pid
        display -t "Download failed for ${theme_name}!" -p 240 -d 2
        return 1
    fi
    kill $download_pid
    
    if [ -f "$output_path" ]; then
        display -t "Download complete!" -p 240
        return 0
    else
        display -t "Download failed!" -p 240 -d 2
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
            show_theme_preview "$current_theme_name"
            ;;
        "B"|"START")
            display_kill
            sh "$UNPACKER"
            exit 0
            ;;
    esac
done
