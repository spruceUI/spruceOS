#!/bin/sh
cd "$(dirname "$0")/.."
export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH

# Directory containing mini games
MINI_GAMES_DIR="./mini_games"
MINI_GAMES_MENU="/tmp/mini_games_menu.txt"

# Make sure the mini games directory exists
if [ ! -d "$MINI_GAMES_DIR" ]; then
    mkdir -p "$MINI_GAMES_DIR"
fi

# Function to generate the mini games menu
generate_mini_games_menu() {
    > "$MINI_GAMES_MENU"
    
    # Look for executable scripts and binaries in the mini games directory
    found_games=0
    for game in "$MINI_GAMES_DIR"/*; do
        if [ -x "$game" ] || [ -f "$game" -a "${game##*.}" = "sh" ]; then
            game_name=$(basename "$game")
            # Format the game name for display (remove extensions, replace underscores with spaces)
            display_name=$(echo "$game_name" | sed 's/\.sh$//' | sed 's/\.elf$//' | sed 's/\.bin$//' | sed 's/_/ /g' | sed 's/^game //')
            # Capitalize first letter of each word
            display_name=$(echo "$display_name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
            echo "$display_name|$game|play" >> "$MINI_GAMES_MENU"
            found_games=$((found_games + 1))
        fi
    done
    
    return $found_games
}

# Check if there are any mini games available
generate_mini_games_menu
if [ $? -eq 0 ]; then
    ./show_message "No mini games found!|Place your mini games in the|$MINI_GAMES_DIR directory." -l a
    exit 0
fi

# Display the title
./show_message "BitPal Mini Games|Choose a game to play!" -l a

# Main menu loop
while true; do
    # Regenerate the menu each time in case games were added/removed
    generate_mini_games_menu
    
    # Show the picker menu with the mini games
    picker_output=$(./picker "$MINI_GAMES_MENU" -b "BACK")
    picker_status=$?
    
    # Handle back button
    if [ $picker_status -ne 0 ]; then
        exit 0
    fi
    
    # Get the game path from the selection
    game_path=$(echo "$picker_output" | cut -d'|' -f2)
    
    # Execute the selected game
    if [ -x "$game_path" ]; then
        # If it's directly executable, run it
        "$game_path"
    elif [ -f "$game_path" -a "${game_path##*.}" = "sh" ]; then
        # If it's a shell script, execute it with sh
        sh "$game_path"
    else
        ./show_message "Cannot run game:|$game_path|The file is not executable." -l a
    fi
    
    # Small delay after game exits before showing menu again
    sleep 1
done

exit 0