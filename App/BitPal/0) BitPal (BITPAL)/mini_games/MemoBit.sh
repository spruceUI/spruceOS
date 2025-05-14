#!/bin/sh
cd "$(dirname "$0")/.."
export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH

# Text faces for BitPal
NEUTRAL_FACE="(-_-)"
EXCITED_FACE="(^o^)"
HAPPY_FACE="(^-^)"
SAD_FACE="(;_;)"

# Show instructions
./show_message "$EXCITED_FACE|BitPal's MemoBit|Remember the sequence|and repeat it back!" -l -a "START" -b "QUIT"
if [ $? -eq 2 ]; then
    exit 0
fi

# Main game loop
score=0
round=1
sequence=""

while true; do
    # Add a new button to the sequence
    if [ $((RANDOM % 2)) -eq 0 ]; then
        sequence="${sequence}A"
    else
        sequence="${sequence}B"
    fi
    
    # Show round info with BitPal face
    ./show_message "$NEUTRAL_FACE|Round $round|Score: $score|Ready, player?" -l -a "GO!" -b "QUIT"
    if [ $? -eq 2 ]; then
        exit 0
    fi
    
    # Show the entire sequence, one button at a time
    for letter in $(echo "$sequence" | grep -o .); do
        ./show_message "$letter" -t 1
    done
    
    # Player's turn with an 80s phrase
    phrase_num=$((RANDOM % 6))
    case $phrase_num in
        0) phrase="Your turn, dude!" ;;
        1) phrase="Totally your move now!" ;;
        2) phrase="Repeat the pattern... Rad!" ;;
        3) phrase="You're up! No bogus moves!" ;;
        4) phrase="Show me your skills!" ;;
        5) phrase="Let's see what you got!" ;;
    esac
    ./show_message "$EXCITED_FACE|$phrase" -t 2
    
    # Now ask for each button in the sequence
    correct=1
    current_pos=1
    
    for letter in $(echo "$sequence" | grep -o .); do
        # Button prompt
        ./show_message "$NEUTRAL_FACE|Button $current_pos?" -l -a "A" -b "B"
        button_result=$?
        
        # Check correct answer: 0 = A pressed, 2 = B pressed
        if [ "$letter" = "A" ] && [ $button_result -eq 0 ]; then
            # Correct: A
            :
        elif [ "$letter" = "B" ] && [ $button_result -eq 2 ]; then
            # Correct: B
            :
        else
            # Wrong button
            correct=0
            break
        fi
        
        current_pos=$((current_pos + 1))
    done
    
    if [ $correct -eq 1 ]; then
        # Player got it right - show 80s success phrase
        success_num=$((RANDOM % 10))
        case $success_num in
            0) success_phrase="Totally radical!" ;;
            1) success_phrase="Excellent!" ;;
            2) success_phrase="Way cool!" ;;
            3) success_phrase="Gnarly moves!" ;;
            4) success_phrase="Tubular!" ;;
            5) success_phrase="Maximum!" ;;
            6) success_phrase="Bodacious!" ;;
            7) success_phrase="Righteous!" ;;
            8) success_phrase="To the max!" ;;
            9) success_phrase="That's bad!" ;;
        esac
        
        new_points=${#sequence}
        score=$((score + new_points))
        ./show_message "$HAPPY_FACE|$success_phrase|Score: $score" -l -a "CONTINUE" -b "QUIT"
        if [ $? -eq 2 ]; then
            exit 0
        fi
        
        # Special milestone messages
        if [ $round -eq 5 ]; then
            ./show_message "$EXCITED_FACE|5 Rounds Complete!|You're like, totally awesome!" -l -a "CONTINUE" -b "QUIT"
            if [ $? -eq 2 ]; then
                exit 0
            fi
        elif [ $round -eq 10 ]; then
            ./show_message "$EXCITED_FACE|10 Rounds!|Whoa! Major brainpower!" -l -a "CONTINUE" -b "QUIT"
            if [ $? -eq 2 ]; then
                exit 0
            fi
        fi
        
        # Next round
        round=$((round + 1))
    else
        # Player made a mistake - 80s game over phrase
        gameover_num=$((RANDOM % 6))
        case $gameover_num in
            0) gameover_phrase="Game Over, man!" ;;
            1) gameover_phrase="Bummer! Game Over!" ;;
            2) gameover_phrase="Like, totally Game Over!" ;;
            3) gameover_phrase="Wipeout! Game Over!" ;;
            4) gameover_phrase="No way! Game Over!" ;;
            5) gameover_phrase="Bogus! Game Over!" ;;
        esac
        
        ./show_message "$SAD_FACE|$gameover_phrase|Round $round|Score: $score" -l -a "OK" -b "QUIT"
        if [ $? -eq 2 ]; then
            exit 0
        fi
        break
    fi
done

# Ask to play again with BitPal face
./show_message "$NEUTRAL_FACE|Play MemoBit again?|Like, totally!" -l -a "YES" -b "NO"
if [ $? -eq 0 ]; then
    exec $0
fi

exit 0