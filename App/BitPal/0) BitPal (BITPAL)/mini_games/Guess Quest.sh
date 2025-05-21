#!/bin/sh
cd "$(dirname "$0")/.."
export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH

# Temporary files
GUESS_MENU="/tmp/guess_quest_menu.txt"
GUESS_OPTIONS="/tmp/guess_quest_options.txt"

# Text faces for BitPal
NEUTRAL_FACE="(-_-)"
EXCITED_FACE="(^o^)"
HAPPY_FACE="(^-^)"
SAD_FACE="(;_;)"

# Initialize the game
secret_number=$((RANDOM % 100 + 1))
guess_count=0
max_guesses=7

# Show game title and instructions
./show_message "$EXCITED_FACE|BitPal's Guess Quest|I'm thinking of a number|between 1 and 100.|Can you guess it in $max_guesses tries?" -l -a "START" -b "QUIT"
if [ $? -eq 2 ]; then
    exit 0
fi

# Main game loop
while [ $guess_count -lt $max_guesses ]; do
    # Show how many guesses remain
    guesses_left=$((max_guesses - guess_count))
    ./show_message "$NEUTRAL_FACE|Guess $((guess_count + 1)) of $max_guesses|Choose a range, dude:" -l -a "SELECT" -b "QUIT"
    if [ $? -eq 2 ]; then
        ./show_message "$SAD_FACE|Bummer! Game Over!|The number was $secret_number.|Better luck next time!" -l -a "OK"
        break
    fi
    
    # Create range menu
    > "$GUESS_MENU"
    echo "1 - 20|low" > "$GUESS_MENU"
    echo "21 - 40|medium-low" >> "$GUESS_MENU"
    echo "41 - 60|medium" >> "$GUESS_MENU"
    echo "61 - 80|medium-high" >> "$GUESS_MENU"
    echo "81 - 100|high" >> "$GUESS_MENU"
    
    # Have player select a range
    picker_output=$(./picker "$GUESS_MENU" -b "BACK")
    picker_status=$?
    
    # Check if player went back
    if [ $picker_status -ne 0 ]; then
        continue
    fi
    
    # Get the selected range
    selected_range=$(echo "$picker_output" | cut -d'|' -f1)
    
    # Set range limits
    case "$selected_range" in
        "1 - 20")
            min=1
            max=20
            ;;
        "21 - 40")
            min=21
            max=40
            ;;
        "41 - 60")
            min=41
            max=60
            ;;
        "61 - 80")
            min=61
            max=80
            ;;
        "81 - 100")
            min=81
            max=100
            ;;
    esac
    
    # Create menu with specific numbers
    > "$GUESS_OPTIONS"
    for i in $(seq $min $max); do
        echo "$i|number" >> "$GUESS_OPTIONS"
    done
    
    # Ask for specific guess
    ./show_message "$NEUTRAL_FACE|Now select the|exact number:" -l -a "SELECT" -b "BACK"
    if [ $? -eq 2 ]; then
        continue  # Go back to range selection
    fi
    
    # Have player select specific number
    number_output=$(./picker "$GUESS_OPTIONS" -b "BACK")
    number_status=$?
    
    # Check if player went back
    if [ $number_status -ne 0 ]; then
        continue  # Go back to range selection
    fi
    
    # Get the guessed number
    guess=$(echo "$number_output" | cut -d'|' -f1)
    guess_count=$((guess_count + 1))
    
    # Check the guess with 80s phrases
    if [ "$guess" -eq "$secret_number" ]; then
        # Player won - use 80s success phrase
        success_num=$((RANDOM % 5))
        case $success_num in
            0) success_phrase="Totally radical!" ;;
            1) success_phrase="That's so righteous!" ;;
            2) success_phrase="Way cool, dude!" ;;
            3) success_phrase="Maximum victory!" ;;
            4) success_phrase="Gnarly moves!" ;;
        esac
        
        ./show_message "$HAPPY_FACE|$success_phrase|The number was $secret_number.|It took you $guess_count guesses." -l -a "AWESOME!"
        guess_count=$max_guesses  # Set to exit the loop
    elif [ "$guess" -lt "$secret_number" ]; then
        # Too low - 80s hint
        hint_num=$((RANDOM % 3))
        case $hint_num in
            0) hint_phrase="No way! Go higher!" ;;
            1) hint_phrase="Bogus! Too low!" ;;
            2) hint_phrase="Chill out and aim higher!" ;;
        esac
        
        ./show_message "$NEUTRAL_FACE|$hint_phrase|$guess is too low." -l -a "CONTINUE"
    else
        # Too high - 80s hint
        hint_num=$((RANDOM % 3))
        case $hint_num in
            0) hint_phrase="Whoa! Too high!" ;;
            1) hint_phrase="Take a chill pill! Lower!" ;;
            2) hint_phrase="Like, totally too high!" ;;
        esac
        
        ./show_message "$NEUTRAL_FACE|$hint_phrase|$guess is too high." -l -a "CONTINUE"
    fi
    
    # Check if player has used all guesses
    if [ $guess_count -ge $max_guesses ] && [ "$guess" -ne "$secret_number" ]; then
        # Game over - 80s phrase
        gameover_num=$((RANDOM % 4))
        case $gameover_num in
            0) gameover_phrase="Game Over, man!" ;;
            1) gameover_phrase="Bummer! Game Over!" ;;
            2) gameover_phrase="Like, totally Game Over!" ;;
            3) gameover_phrase="Wipeout! Game Over!" ;;
        esac
        
        ./show_message "$SAD_FACE|$gameover_phrase|You ran out of guesses.|The number was $secret_number." -l -a "OK"
    fi
done

# Ask to play again
./show_message "$NEUTRAL_FACE|Play Guess Quest again?|Like, totally!" -l -a "YES" -b "NO"
if [ $? -eq 0 ]; then
    # Clean up and restart
    rm -f "$GUESS_MENU" "$GUESS_OPTIONS"
    exec $0
fi

# Clean up temporary files
rm -f "$GUESS_MENU" "$GUESS_OPTIONS"

exit 0