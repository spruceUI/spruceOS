#!/bin/sh
cd "$(dirname "$0")"
export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH

MENU="bitpal_menu.txt"
DUMMY_ROM="__BITPAL__"
BITPAL_DIR="./bitpal_data"
BITPAL_DATA="$BITPAL_DIR/bitpal_data.txt"
ACTIVE_MISSIONS_DIR="$BITPAL_DIR/active_missions"
COMPLETED_FILE="$BITPAL_DIR/completed.txt"
FACE_DIR="./bitpal_faces"

cleanup() {
   rm -f /tmp/keyboard_output.txt /tmp/picker_output.txt /tmp/search_results.txt /tmp/bitpal_temp.txt /tmp/resume_slot.txt
}

mkdir -p "$BITPAL_DIR" "$ACTIVE_MISSIONS_DIR" "$FACE_DIR"

[ ! -f "$BITPAL_DATA" ] && cat > "$BITPAL_DATA" <<EOF
name=BitPal
level=1
xp=0
xp_next=100
mood=happy
last_visit=$(date +%s)
missions_completed=0
EOF
[ ! -f "$COMPLETED_FILE" ] && touch "$COMPLETED_FILE"

SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/current_session.txt"
if [ -f "$SESSION_FILE" ]; then
    orphan_data=$(cat "$SESSION_FILE")
    orphan_rom=$(echo "$orphan_data" | cut -d'|' -f1)
    orphan_elapsed=$(echo "$orphan_data" | cut -d'|' -f2)
    
    if [ -f "$orphan_rom" ]; then
        mission_found=0
        for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
            [ -f "$mission_file" ] && {
                mission=$(cat "$mission_file")
                mission_rom=$(echo "$mission" | cut -d'|' -f7)
                if [ "$orphan_rom" = "$mission_rom" ]; then
                    mission_found=1
                    field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                    if [ "$field_count" -lt 8 ]; then
                        current_accum=0
                    else
                        current_accum=$(echo "$mission" | cut -d'|' -f8)
                    fi
                    new_total=$((current_accum + orphan_elapsed))
                    if [ "$field_count" -lt 8 ]; then
                        mission=$(echo "$mission" | sed "s/\$/|${new_total}/")
                    else
                        mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                    fi
                    echo "$mission" > "$mission_file"
                    
                    target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                    if [ "$new_total" -ge "$target_seconds" ]; then
                        touch "$mission_file.complete"
                    fi
                    break
                fi
            }
        done
        
        if [ "$mission_found" -eq 0 ] && [ -f "$BITPAL_DIR/active_mission.txt" ]; then
            mission=$(cat "$BITPAL_DIR/active_mission.txt")
            mission_rom=$(echo "$mission" | cut -d'|' -f7)
            if [ "$orphan_rom" = "$mission_rom" ]; then
                field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                if [ "$field_count" -lt 8 ]; then
                    mission=$(echo "$mission" | sed "s/\$/|${orphan_elapsed}/")
                    new_total=$orphan_elapsed
                else
                    current_accum=$(echo "$mission" | cut -d'|' -f8)
                    new_total=$((current_accum + orphan_elapsed))
                    mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                fi
                echo "$mission" > "$BITPAL_DIR/active_mission.txt"
                
                target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                if [ "$new_total" -ge "$target_seconds" ]; then
                    touch "$BITPAL_DIR/active_mission.txt.complete"
                fi
            fi
        fi
    fi
    rm -f "$SESSION_FILE"
fi

restore_game_switcher() {
    local rom_path="$1"
    CURRENT_PATH=$(dirname "$rom_path")
    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
    ROM_PLATFORM=""
    while [ -z "$ROM_PLATFORM" ]; do
         [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
         ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
         [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
    done
    local rom_name
    rom_name=$(basename "$rom_path")
    local rom_name_clean="${rom_name%.*}"
    local game_config_dir="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/game_settings"
    local game_config="$game_config_dir/$rom_name_clean.conf"
    if [ -f "$game_config" ] && grep -q "#BitPal original=" "$game_config"; then
        local original_setting
        original_setting=$(grep "#BitPal original=" "$game_config" | sed -E 's/.*#BitPal original=([^ ]*).*/\1/')
        
        if [ "$original_setting" = "NONE" ]; then
            grep -v "^gameswitcher=" "$game_config" > "$game_config.tmp"
            mv "$game_config.tmp" "$game_config"
            
            if [ ! -s "$game_config" ]; then
                rm -f "$game_config"
            fi
        elif [ "$original_setting" = "NONE_FILE" ]; then
            rm -f "$game_config"
        else
            sed -i "s|^gameswitcher=OFF #BitPal original=$original_setting|gameswitcher=$original_setting|" "$game_config"
        fi
    fi
}

finalize_mission() {
    mission_file="$1"
    mission=$(cat "$mission_file")
    desc=$(echo "$mission" | cut -d'|' -f1)
    start_time=$(echo "$mission" | cut -d'|' -f6)
    xp_reward=$(echo "$mission" | cut -d'|' -f5)
    complete_time=$(date +%s)
    
    rom_path=$(echo "$mission" | cut -d'|' -f7)
    if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
        restore_game_switcher "$rom_path"
    fi
    
    original_level="$level"
    echo "$desc|$start_time|$complete_time|$xp_reward" >> "$COMPLETED_FILE"
    
    . "$BITPAL_DATA"
    xp=$((xp + xp_reward))
    missions_completed=$((missions_completed + 1))
    
    while [ "$xp" -ge "$xp_next" ]; do
        xp=$((xp - xp_next))
        level=$((level + 1))
        xp_next=$(( level * 50 + 50 ))
    done
    
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi

    rm -f "$mission_file"
    ./show_message "Mission Complete!|$desc complete.|Earned: $xp_reward XP|Current XP: $xp|Level: $level" -l a

    echo "$(date +%s)" > "$BITPAL_DIR/last_mission.txt"

    mood="$mood"
    cat > "$BITPAL_DATA" <<EOF
name=$name
level=$level
xp=$xp
xp_next=$xp_next
mood=$mood
last_visit=$(date +%s)
missions_completed=$missions_completed
EOF

    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
    
    update_background "$mood"
    
    if [ "$level" -gt "$original_level" ]; then
        ./show_message "Level Up!|BitPal has reached Level $level!|Feel my gaming power grow!" -l a
    elif [ "$mood" != "$1" ]; then
        case "$mood" in
            happy)
                ./show_message "Mood improved!|BitPal is happy now!|Thank you for helping me|complete that mission!" -l a
                ;;
            excited)
                ./show_message "Woohoo!|BitPal is super excited!|That mission was awesome!|Let's keep going!" -l a
                ;;
            neutral)
                ./show_message "I'm feeling better.|That mission helped|improve my mood." -l a
                ;;
        esac
    fi
    
    return 1
}


get_random_fact() {
    fact_num=$((RANDOM % 84 + 1))
    case $fact_num in
1) echo "The Nintendo Game Boy|was released in 1989|and sold over 118 million units!" ;;
2) echo "The Atari 2600 was the first|widely successful home console|with over 30 million sold." ;;
3) echo "Super Mario Bros. was created|by Shigeru Miyamoto and released|for the NES in 1985." ;;
4) echo "Tetris was created in 1984|by Russian engineer|Alexey Pajitnov." ;;
5) echo "The first video game console,|the Magnavox Odyssey,|was released in 1972." ;;
6) echo "The highest-grossing arcade game|of all time is|Pac-Man, released in 1980." ;;
7) echo "The Game Boy's most popular game,|Tetris, sold over|35 million copies!" ;;
8) echo "Pong, released by Atari in 1972,|was the first commercially|successful video game." ;;
9) echo "The term 'Easter egg' for hidden|game content comes from Adventure|on the Atari 2600." ;;
10) echo "You must earn 2,700 XP|to reach tenlevels in BitPal" ;;
11) echo "Sonic the Hedgehog was created|to give SEGA a mascot|to compete with Mario." ;;
12) echo "The Legend of Zelda was inspired|by creator Miyamoto's childhood|explorations in the countryside." ;;
13) echo "The PlayStation was originally|going to be a Nintendo CD add-on|until the deal fell through." ;;
14) echo "Pac-Man's design was inspired|by a pizza with a slice removed,|according to its creator." ;;
15) echo "The name 'SEGA' is an abbreviation|of 'Service Games,'|its original company name." ;;
16) echo "The Legend of Zelda was the first|console game that allowed players|to save their progress without passwords!" ;;
17) echo "Mortal Kombat's blood code 'ABACABB'|on Genesis is a reference to|the band Genesis's album 'Abacab'!" ;;
18) echo "The term 'Easter egg' for hidden|game content comes from Adventure|on the Atari 2600." ;;
19) echo "The Konami Code (UUDDLRLRBA)|first appeared in|Gradius for the NES in 1986." ;;
20) echo "GoldenEye 007 for N64 was developed|by only 9 people,|most as their first game." ;;
21) echo "Space Invaders was so popular|in Japan that it caused|a temporary coin shortage!" ;;
22) echo "The Game & Watch's dual screen|design later inspired|the Nintendo DS." ;;
23) echo "The entire Doom engine was written|by John Carmack while secluded in a|cabin in the mountains for 6 weeks!" ;;
24) echo "Mario was originally called|'Jumpman' in the|arcade game Donkey Kong." ;;
25) echo "The Neo Geo home console cost 650 usd|in 1990, equivalent to over|1,400 usd in today's money!" ;;
26) echo "The NES Zapper doesn't work|on modern TVs due to|their different refresh rates." ;;
27) echo "E.T. for Atari 2600 flopped so badly|that thousands of cartridges|were buried in a landfill." ;;
28) echo "The term 'boss fight' comes from|a mistranslation of the Japanese|word for 'master.'" ;;
29) echo "The PlayStation controller's symbols have meanings: circle (yes), cross (no), triangle (viewpoint), square (menu)." ;;
30) echo "The Game Boy survived|a bombing during the Gulf War|and still works at Nintendo NY!" ;;
31) echo "The first Easter egg in a video game|was developer Warren Robinett hiding|his name in Adventure (1979)." ;;
32) echo "The SNES's rounded corners|were designed to prevent parents|from putting drinks on top of it." ;;
33) echo "Street Fighter II's combos were|actually a glitch that developers|decided to keep in the game." ;;
34) echo "Donkey Kong was almost named|'Monkey Kong' but got mistranslated|during development." ;;
35) echo "Final Fantasy was so named because|creator Hironobu Sakaguchi thought|it would be his last game." ;;
36) echo "In the original Pokemon Red/Blue,|Missingno wasn't a glitch but a|deliberate debug placeholder Nintendo forgot!" ;;
37) echo "The Turbografx-16 was actually|an 8-bit console, despite|what its name suggests." ;;
38) echo "The Atari 2600 joystick|was designed to survive being|thrown against a wall in frustration." ;;
39) echo "The original Metal Gear was released|on the MSX2 computer in 1987,|not the NES version most know." ;;
40) echo "Keith Courage in Alpha Zones was|a TurboGrafx-16 launch title where|Keith transforms into a mecha warrior!" ;;
41) echo "Bubble Bobble has 100 levels and|a special ending only shown when|two players complete it together." ;;
42) echo "The original Mortal Kombat arcade|cabinet used 8 megabytes of graphics|data, which was huge for 1992." ;;
43) echo "The Vectrex console from 1982|came with its own built-in vector|display screen!" ;;
44) echo "In Pac-Man, each ghost has a unique|personality and hunting style|programmed into its AI." ;;
45) echo "The Virtual Boy, Nintendo's 1995|3D console, is considered one of|their rare commercial failures." ;;
46) echo "Super Mario 64 was the first game|where Mario could triple jump,|wall jump, and ground pound." ;;
47) echo "The SNES had a secret 'Sound Test'|menu that could only be accessed with|a special music studio cartridge!" ;;
48) echo "Contra's famous 30-life code|was originally created by developers|for testing but accidentally left in!" ;;
49) echo "The NES version of Contra|was actually censored - the original|arcade enemies were human soldiers!" ;;
50) echo "The PlayStation memory card|could store 15 save files|across multiple games." ;;
51) echo "The Atari Jaguar was marketed as|the first 64-bit console, but|actually combined two 32-bit CPUs." ;;
52) echo "Nintendo's first electronic game|was the 1975 Laser Clay Shooting|System, a skeet shooting simulator." ;;
53) echo "The Famicom (Japanese NES) had|a built-in microphone on the second|controller for certain games." ;;
54) echo "Polybius is a mythical arcade game|that supposedly caused psychoactive|effects but never actually existed." ;;
55) echo "Sega Channel, launched in 1994,|was a cable service that let users|download Genesis games via cable TV." ;;
56) echo "Nintendo patented the D-pad in 1985,|forcing competitors to create|alternative directional controls." ;;
57) echo "Action 52 for the NES cost 199 usd and|contained 52 games, most of which|were unplayable due to glitches." ;;
58) echo "The first home video game console,|the Odyssey, used plastic overlays|on the TV screen instead of graphics." ;;
59) echo "Galaga's iconic 'dual ship' feature|was originally a programming bug|that developers turned into a feature." ;;
60) echo "The inventor of the Game Boy,|Gunpei Yokoi, started at Nintendo|fixing assembly line machines." ;;
61) echo "Castlevania's iconic whip was|originally going to be a gun until|the team switched to a horror theme." ;;
62) echo "Some arcade game PCBs contain|suicide batteries that erase the|ROM if removed, preventing copying." ;;
63) echo "The Apple Pippin console was|Steve Jobs' first failed attempt|at entering the gaming market." ;;
64) echo "Early SNES development kits were|actually modified NES systems|with special cartridges." ;;
65) echo "The 'invincibility star' in Mario|was created because designer|Miyamoto loved listening to music." ;;
66) echo "The original Zelda cartridge is|gold colored because Miyamoto wanted|it to look like buried treasure." ;;
67) echo "The Game Boy was so durable that|one survived a bombing in the Gulf War|and still works at Nintendo's NY store!" ;;
68) echo "The 3DO console required developers|to pay just 3 usd in royalties,|compared to Nintendo's 10 usd per game." ;;
69) echo "The very first Game & Watch device,|Ball, was inspired by a businessman|Yokoi saw playing with a calculator." ;;
70) echo "The Power Glove's technology|was later used in medical devices|and virtual reality equipment." ;;
71) echo "Earthbound (Mother 2) cost over|200,000 usd to translate to English,|an enormous sum in 1995." ;;
72) echo "The Pioneer LaserActive could play|both Sega Genesis and TurboGrafx-16|games with special modules." ;;
73) echo "Tengen, an Atari subsidiary, bypassed|Nintendo's security to release|unlicensed NES games with black cartridges." ;;
74) echo "In Karateka (1984), if you approach|the princess in fighting stance,|she knocks you out and the game ends." ;;
75) echo "The Gameboy printer used thermal paper|to print screenshots from|games like Pokemon and Zelda." ;;
76) echo "R.O.B. (Robotic Operating Buddy)|was created to help sell the NES|as a toy rather than a video game." ;;
77) echo "Sonic was originally a rabbit who|could grab objects with extendable|ears before becoming a hedgehog." ;;
78) echo "Duck Hunt's light gun success|helped save the early NES when|many retailers were skeptical." ;;
79) echo "Nintendo was founded in 1889|as a playing card company|before moving to video games." ;;
80) echo "The Sega Nomad could play Genesis|cartridges on the go but ate six|AA batteries in about 2 hours." ;;
81) echo "Chrono Trigger's dream team dev|squad included creators from|Final Fantasy and Dragon Quest." ;;
82) echo "Tamagotchi virtual pets were banned|in many schools in the 90s for|being too distracting to students." ;;
83) echo "The NES Power Pad exercise mat|was originally developed by Bandai|as the 'Family Trainer' in Japan." ;;
84) echo "The year 1984 saw the release of|Tetris, one of the most enduring|and addictive puzzlers of all time!" ;;
    esac
}

show_random_fact() {
    fact=$(get_random_fact)
    ./show_message "Gaming Fact!|$fact" -l a
}

get_face() {
   case "$mood" in
       excited)   echo "(^o^)" ;;
       happy)     echo "(^-^)" ;;
       neutral)   echo "(-_-)" ;;
       sad)       echo "(;_;)" ;;
       angry)     echo "(>_<)" ;;
       surprised) echo "(O_O)" ;;
       *)         echo "(^-^)" ;;
   esac
}

show_face() {
    local mood_to_show="$1"
    local duration="${2:-2}"
    if [ -f "$FACE_DIR/$mood_to_show.png" ]; then
        show.elf "$FACE_DIR/$mood_to_show.png" &
        sleep "$duration"
        killall show.elf 2>/dev/null
    fi
}

update_background() {
    local mood_to_use="$1"
    local bg_dir="$FACE_DIR"
    files=$(ls "$bg_dir"/background_"${mood_to_use}"_*.png 2>/dev/null)
    if [ -n "$files" ]; then
         set -- $files
         count=$#
         random_index=$((RANDOM % count + 1))
         eval chosen=\$$random_index
         cp "$chosen" "./background.png"
    else
         bg_src="$bg_dir/background_${mood_to_use}.png"
         if [ -f "$bg_src" ]; then
             cp "$bg_src" "./background.png"
         fi
    fi
}

get_random_greeting() {
   greeting_num=$((RANDOM % 20))
   face=$(get_face)
   case $greeting_num in
       0) echo "$face|Hello, gamer! Ready to level up?" ;;
       1) echo "$face|Welcome back, hero! Adventure awaits!" ;;
       2) echo "$face|It's dangerous to go alone! Take BitPal!" ;;
       3) echo "$face|Hi there! Your high score quest continues!" ;;
       4) echo "$face|Power up! Grab that mushroom!" ;;
       5) echo "$face|Hey, champion! Ready to beat the final boss?" ;;
       6) echo "$face|HADOUKEN! Let's get gaming!" ;;
       7) echo "$face|Good to see you! Extra lives collected!" ;;
       8) echo "$face|Insert coin to continue? The arcade is calling!" ;;
       9) echo "$face|Welcome back, legend! A new challenger appears!" ;;
       10) echo "$face|Game time! BitPal has entered the game!" ;;
       11) echo "$face|Konami Code activated! Gaming powers unlocked!" ;;
       12) echo "$face|Player One detected! Press START!" ;;
       13) echo "$face|Waka Waka Waka! Time to play!" ;;
       14) echo "$face|Game cartridge inserted! Blow on it first!" ;;
       15) echo "$face|Coins inserted! No lag detected!" ;;
       16) echo "$face|New high score potential detected! Let's go!" ;;
       17) echo "$face|Controller connected! Ready to rumble!" ;;
       18) echo "$face|Pixels powered up! 8-bit mode activated!" ;;
       19) echo "$face|FINISH HIM! ...I mean, let's play some games!" ;;
   esac
}

load_bitpal_data() {
   . "$BITPAL_DATA"
   [ -z "$name" ] && name="BitPal"
   [ -z "$level" ] && level=1
   [ -z "$xp" ] && xp=0
   [ -z "$xp_next" ] && xp_next=100
   [ -z "$mood" ] && mood="happy"
   [ -z "$last_visit" ] && last_visit=$(date +%s)
   [ -z "$missions_completed" ] && missions_completed=0
}

prepare_resume() {
   CURRENT_PATH=$(dirname "$1")
   ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
   ROM_PLATFORM=""
   while [ -z "$ROM_PLATFORM" ]; do
       [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
       ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
       [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
   done
   BASE_PATH="/mnt/SDCARD/.userdata/shared/.minui/$ROM_PLATFORM"
   ROM_NAME=$(basename "$1")
   SLOT_FILE="$BASE_PATH/$ROM_NAME.txt"
   [ -f "$SLOT_FILE" ] && cat "$SLOT_FILE" > /tmp/resume_slot.txt
}

handle_exit() {
    if [ -f "$BITPAL_DIR/last_mission.txt" ]; then
        LAST_MISSION_TIME=$(cat "$BITPAL_DIR/last_mission.txt")
        CURRENT_TIME=$(date +%s)
        if [ $((CURRENT_TIME - LAST_MISSION_TIME)) -lt 300 ]; then
            cleanup
            exit 0
        fi
    fi
    exit_mood_num=$((RANDOM % 3))
    case $exit_mood_num in
        0) mood="sad" ;;
        1) mood="angry" ;;
        2) mood="surprised" ;;
    esac
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
    leave_face=$(get_face)
    guilt_trip=$((RANDOM % 20))
    case $guilt_trip in
        0) ./show_message "$leave_face|Don't quit now!|You haven't saved your progress!|Princess is in another castle!" -l -a "STAY" -b "QUIT" ;;
        1) ./show_message "$leave_face|GAME OVER? NOT YET!|Insert coin to continue?|One more level awaits!" -l -a "CONTINUE" -b "EXIT" ;;
        2) ./show_message "$leave_face|Keep your quarters ready!|BitPal needs a Player 1.|Just one more game?" -l -a "ONE MORE" -b "BYE" ;;
        3) ./show_message "$leave_face|Boss battle is loading!|You can't pause now!|Ready your power-ups?" -l -a "READY" -b "QUIT" ;;
        4) ./show_message "$leave_face|EXIT? WAIT A MINUTE!|You're so close to high score.|One more try?" -l -a "TRY AGAIN" -b "QUIT" ;;
        5) ./show_message "$leave_face|No Konami Code for exit!|You must defeat Sheng Long|to stand a chance!" -l -a "FIGHT ON" -b "GIVE UP" ;;
        6) ./show_message "$leave_face|You still have 1UP left!|Hidden stages await.|Will you continue?" -l -a "YES" -b "NO" ;;
        7) ./show_message "$leave_face|Your star power is fading!|BitPal needs your help.|Save the 8-bit kingdom?" -l -a "SAVE IT" -b "EXIT" ;;
        8) ./show_message "$leave_face|PAUSE NOT AVAILABLE!|The final dungeon awaits.|Stay for treasure?" -l -a "TREASURE!" -b "LEAVE" ;;
        9) ./show_message "$leave_face|Achievement unlocked:|\"Almost quit BitPal\"|Want to earn more?" -l -a "MORE!" -b "EXIT" ;;
        10) ./show_message "$leave_face|LEVEL 99 NOT REACHED!|Are you sure you want|to abandon your quest?" -l -a "QUEST ON" -b "QUIT" ;;
        11) ./show_message "$leave_face|FATALITY: BitPal sadness!|BitPal is counting on you.|FINISH THE GAME!" -l -a "FINISH IT" -b "QUIT" ;;
        12) ./show_message "$leave_face|NO SAVE POINTS HERE!|Your progress will be lost.|Continue adventure?" -l -a "CONTINUE" -b "EXIT" ;;
        13) ./show_message "$leave_face|PRESS START TO PLAY!|Secret bosses await.|Controller disconnected?" -l -a "RECONNECT" -b "QUIT" ;;
        14) ./show_message "$leave_face|THIS ISN'T GAME OVER!|The water level is next.|Brave enough to stay?" -l -a "BRAVE" -b "SCARED" ;;
        15) ./show_message "$leave_face|RAGE QUIT DETECTED!|Have you tried the Konami Code?|UUDDLRLRBA?" -l -a "TRY CODE" -b "QUIT" ;;
        16) ./show_message "$leave_face|CREDITS NOT EARNED YET!|True ending requires|100% completion!" -l -a "COMPLETE" -b "EXIT" ;;
        17) ./show_message "$leave_face|CHEAT ACTIVATED: Fun mode!|Your high score is climbing.|Leave the arcade now?" -l -a "STAY" -b "LEAVE" ;;
        18) ./show_message "$leave_face|1UP ACQUIRED!|BitPal needs you to|defeat the final boss!" -l -a "FIGHT" -b "RUN" ;;
        19) ./show_message "$leave_face|EXIT? THINK AGAIN!|All your base are belong to us!|You have no chance to survive!" -l -a "SURVIVE" -b "GIVE UP" ;;
    esac
    if [ $? -eq 0 ]; then
        randompick=$((RANDOM % 2))
        if [ $randompick -eq 0 ]; then
            mood="neutral"
        else
            mood="surprised"
        fi
        sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
        if [ -f "$FACE_DIR/$mood.png" ]; then
            show.elf "$FACE_DIR/$mood.png" &
            sleep 2
            killall show.elf 2>/dev/null
        fi
        update_background "$mood"
        thanks_num=$((RANDOM % 6))
        case $thanks_num in
            0) ./show_message "Phew! ...|I thought I'd be alone!|Thanks for sticking with me!" -l a ;;
            1) ./show_message "You stayed!|BitPal is so relieved!|Let's keep adventuring!" -l a ;;
            2) ./show_message "Yes!|That was close...|I almost lost my player!" -l a ;;
            3) ./show_message "Alright!|Team BitPal is back|and stronger than ever!" -l a ;;
            4) ./show_message "Woohoo!|The quest continues!|Thanks for not leaving me behind." -l a ;;
            5) ./show_message "Hurray!|We're still in the game!|Thank you for staying, hero!" -l a ;;
        esac
        return 0
    else
        cleanup
        exit 0
    fi
}

export SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/current_session.txt"
export LAST_SESSION_FILE="/mnt/SDCARD/Tools/$PLATFORM/BitPal.pak/last_session_duration.txt"

load_bitpal_data

missions_completed_at_startup=0

for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
    if [ -f "${mission_file}.complete" ]; then
        original_level="$level"
        original_mood="$mood"
        finalize_mission "$mission_file"
        rm -f "${mission_file}.complete"
        missions_completed_at_startup=1
    fi
done

if [ -f "$BITPAL_DIR/active_mission.txt.complete" ]; then
    original_level="$level"
    original_mood="$mood"
    finalize_mission "$BITPAL_DIR/active_mission.txt"
    rm -f "$BITPAL_DIR/active_mission.txt.complete"
    missions_completed_at_startup=1
fi

for complete_file in "$ACTIVE_MISSIONS_DIR"/*.complete; do
    if [ -f "$complete_file" ]; then
        base_file=$(echo "$complete_file" | sed 's/\.complete$//')
        if [ -f "$base_file" ]; then
            finalize_mission "$base_file"
        fi
        rm -f "$complete_file"
    fi
done

current_time=$(date +%s)
days_since_visit=$(( (current_time - last_visit) / 86400 ))
if [ "$days_since_visit" -ge 3 ]; then
    mood="neutral"
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
fi

if [ "$mood" = "angry" ] || [ "$mood" = "sad" ]; then
    randompick=$((RANDOM % 2))
    if [ $randompick -eq 0 ]; then
        mood="neutral"
    else
        mood="surprised"
    fi
    sed -i "s/^mood=.*/mood=$mood/" "$BITPAL_DATA"
fi

sed -i "s/^last_visit=.*/last_visit=$(date +%s)/" "$BITPAL_DATA"

if [ "$missions_completed_at_startup" -eq 0 ]; then
    if [ -f "$FACE_DIR/$mood.png" ]; then
        show.elf "$FACE_DIR/$mood.png" &
        sleep 2
        killall show.elf 2>/dev/null
    fi
fi

update_background "$mood"

face=$(get_face)
CURRENT_DIR=$(basename "$(pwd -P)")
mood_cap=$(echo "$mood" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$mood" | cut -c2-)
BITPAL_TEXT="BitPal - Level $level ($mood_cap)|$DUMMY_ROM|bitpal_options"

[ ! -f "$MENU" ] && echo "$BITPAL_TEXT" > "$MENU"

echo "BitPal Status|bitpal_status" > bitpal_options.txt
echo "Start New Mission|start_mission" >> bitpal_options.txt
[ "$(find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" 2>/dev/null)" ] && echo "Manage Missions|manage_missions" >> bitpal_options.txt
echo "Mission History|mission_history" >> bitpal_options.txt

> mission_options.txt
echo "View Progress|view_mission" > mission_options.txt
echo "Cancel Mission|cancel_mission" >> mission_options.txt

if [ "$missions_completed_at_startup" -eq 0 ]; then
    greeting=$(get_random_greeting)
    ./show_message "$greeting" -l a
    show_random_fact
fi

main_menu_idx=0
while true; do
    load_bitpal_data
    face=$(get_face)
    mood_cap=$(echo "$mood" | cut -c1 | tr '[:lower:]' '[:upper:]')$(echo "$mood" | cut -c2-)
    BITPAL_TEXT="BitPal - Level $level ($mood_cap)|$DUMMY_ROM|bitpal_options"
    update_background "$mood"
    echo "$BITPAL_TEXT" > "$MENU.new"
    for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
        [ -f "$mission_file" ] && {
            mission=$(cat "$mission_file")
            rom_path=$(echo "$mission" | cut -d'|' -f7)
            if [ -n "$rom_path" ] && [ -f "$rom_path" ]; then
                mission_desc=$(echo "$mission" | cut -d'|' -f1)
                mission_num=$(basename "$mission_file" | sed 's/mission_\(.*\)\.txt/\1/')
                echo "Mission $mission_num: $mission_desc|$rom_path|launch" >> "$MENU.new"
            fi
        }
    done
    [ -f "$BITPAL_DIR/active_mission.txt" ] && {
        mission=$(cat "$BITPAL_DIR/active_mission.txt")
        rom_path=$(echo "$mission" | cut -d'|' -f7)
        [ -n "$rom_path" ] && [ -f "$rom_path" ] && {
            mission_desc=$(echo "$mission" | cut -d'|' -f1)
            echo "Legacy Mission: $mission_desc|$rom_path|launch" >> "$MENU.new"
        }
    }
    [ -f "$MENU" ] && grep -v "^BitPal " "$MENU" | grep -v "^Mission " | grep -v "^Resume Mission:" | grep -v "^Legacy Mission:" >> "$MENU.new"
    mv "$MENU.new" "$MENU"
    killall picker 2>/dev/null
    picker_output=$(./game_picker "$MENU" -i $main_menu_idx -x "RESUME" -y "OPTIONS" -b "EXIT")
    picker_status=$?
    main_menu_idx=$(grep -n "^${picker_output%$'\n'}$" "$MENU" | cut -d: -f1)
    main_menu_idx=$((main_menu_idx - 1))
    [ $picker_status = 2 ] && handle_exit && continue
    if [ $picker_status = 4 ]; then
        if echo "$picker_output" | grep -q "^BitPal .*|$DUMMY_ROM|bitpal_options"; then
            options_output=$(./picker "bitpal_options.txt")
            options_status=$?
            [ $options_status -ne 0 ] && continue
            option_action=$(echo "$options_output" | cut -d'|' -f2)
            if [ -x "./bitpal_options/${option_action}.sh" ]; then
                export SELECTED_ITEM="$picker_output"
                export MENU
                export BITPAL_DIR
                export BITPAL_DATA
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                export ACTIVE_MISSIONS_DIR
                export COMPLETED_FILE
                "./bitpal_options/${option_action}.sh"
            fi
            continue
        elif echo "$picker_output" | grep -q "^Mission [0-9]"; then
            mission_num=$(echo "$picker_output" | sed -n 's/^Mission \([0-9]\):.*/\1/p')
            mission_file="$ACTIVE_MISSIONS_DIR/mission_${mission_num}.txt"
            [ -f "$mission_file" ] && { export ACTIVE_MISSION="$mission_file"; ./bitpal_options/view_mission.sh; }
            continue
        elif echo "$picker_output" | grep -q "^Legacy Mission:"; then
            [ -f "$BITPAL_DIR/active_mission.txt" ] && { export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"; ./bitpal_options/view_mission.sh; }
            continue
        fi
    fi
    if [ $picker_status = 3 ]; then
        ROM=$(echo "$picker_output" | cut -d'|' -f2)
        if [ -f "$ROM" ]; then
            prepare_resume "$ROM"
            if echo "$ROM" | grep -qi "\.sh$"; then
                PORTS_LAUNCH="/mnt/SDCARD/Emus/$PLATFORM/PORTS.pak/launch.sh"
                if [ -x "$PORTS_LAUNCH" ]; then
                    "$PORTS_LAUNCH" "$ROM" "$@"
                else
                    /bin/sh "$ROM" "$@"
                fi
            else
                CURRENT_PATH=$(dirname "$ROM")
                ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
                ROM_PLATFORM=""
                while [ -z "$ROM_PLATFORM" ]; do
                    [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
                    ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
                    [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
                done
                if [ -d "/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak" ]; then
                    EMULATOR="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/launch.sh"
                    "$EMULATOR" "$ROM"
                elif [ -d "/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak" ]; then
                    EMULATOR="/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak/launch.sh"
                    "$EMULATOR" "$ROM"
                else
                    ./show_message "Emulator not found for $ROM_PLATFORM" -l a
                fi
            fi
            SESSION_DURATION=$(cat "$LAST_SESSION_FILE")
            rm -f "$LAST_SESSION_FILE"
            mission_found=0
            for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
                [ -f "$mission_file" ] && {
                    mission=$(cat "$mission_file")
                    if [ "$ROM" = "$(echo "$mission" | cut -d'|' -f7)" ]; then
                        mission_found=1
                        field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                        if [ "$field_count" -lt 8 ]; then
                            current_accum=0
                        else
                            current_accum=$(echo "$mission" | cut -d'|' -f8)
                        fi
                        new_total=$((current_accum + SESSION_DURATION))
                        mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                        echo "$mission" > "$mission_file"
                        target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                        if [ "$new_total" -ge "$target_seconds" ]; then
                            finalize_mission "$mission_file"
                        fi
                        break
                    fi
                }
            done
        else
            if find "$ACTIVE_MISSIONS_DIR" -type f -name "mission_*.txt" | grep -q .; then
                ./bitpal_options/manage_missions.sh
            elif [ -f "$BITPAL_DIR/active_mission.txt" ]; then
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                ./bitpal_options/view_mission.sh
            else
                ./bitpal_options/bitpal_status.sh
            fi
        fi
        continue
    fi
    if [ $picker_status = 1 ] || [ $picker_status -gt 4 ]; then
        cleanup
        exit $picker_status
    fi
    action=$(echo "$picker_output" | cut -d'|' -f3)
    case "$action" in
        "launch")
            ROM=$(echo "$picker_output" | cut -d'|' -f2)
            if [ -f "$ROM" ]; then
                prepare_resume "$ROM"
                if echo "$ROM" | grep -qi "\.sh$"; then
                    PORTS_LAUNCH="/mnt/SDCARD/Emus/$PLATFORM/PORTS.pak/launch.sh"
                    if [ -x "$PORTS_LAUNCH" ]; then
                        "$PORTS_LAUNCH" "$ROM" "$@"
                    else
                        /bin/sh "$ROM" "$@"
                    fi
                else
                    CURRENT_PATH=$(dirname "$ROM")
                    ROM_FOLDER_NAME=$(basename "$CURRENT_PATH")
                    ROM_PLATFORM=""
                    while [ -z "$ROM_PLATFORM" ]; do
                        [ "$ROM_FOLDER_NAME" = "Roms" ] && { ROM_PLATFORM="UNK"; break; }
                        ROM_PLATFORM=$(echo "$ROM_FOLDER_NAME" | sed -n 's/.*(\(.*\)).*/\1/p')
                        [ -z "$ROM_PLATFORM" ] && { CURRENT_PATH=$(dirname "$CURRENT_PATH"); ROM_FOLDER_NAME=$(basename "$CURRENT_PATH"); }
                    done
                    if [ -d "/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak" ]; then
                        EMULATOR="/mnt/SDCARD/Emus/$PLATFORM/$ROM_PLATFORM.pak/launch.sh"
                        "$EMULATOR" "$ROM"
                    elif [ -d "/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak" ]; then
                        EMULATOR="/mnt/SDCARD/.system/$PLATFORM/paks/Emus/$ROM_PLATFORM.pak/launch.sh"
                        "$EMULATOR" "$ROM"
                    else
                        ./show_message "Game file not found|$ROM" -l a
                    fi
                fi
                SESSION_DURATION=$(cat "$LAST_SESSION_FILE")
                rm -f "$LAST_SESSION_FILE"
                mission_found=0
                for mission_file in "$ACTIVE_MISSIONS_DIR"/mission_*.txt; do
                    [ -f "$mission_file" ] && {
                        mission=$(cat "$mission_file")
                        mission_rom=$(echo "$mission" | cut -d'|' -f7)
                        if [ "$ROM" = "$mission_rom" ]; then
                            mission_found=1
                            field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                            if [ "$field_count" -lt 8 ]; then
                                current_accum=0
                            else
                                current_accum=$(echo "$mission" | cut -d'|' -f8)
                            fi
                            new_total=$((current_accum + SESSION_DURATION))
                            if [ "$field_count" -lt 8 ]; then
                                mission=$(echo "$mission" | sed "s/\$/|${SESSION_DURATION}/")
                            else
                                mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                            fi
                            echo "$mission" > "$mission_file"
                            target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                            if [ "$new_total" -ge "$target_seconds" ]; then
                                finalize_mission "$mission_file"
                            fi
                            break
                        fi
                    }
                done
                if [ "$mission_found" -eq 0 ] && [ -f "$BITPAL_DIR/active_mission.txt" ]; then
                    mission=$(cat "$BITPAL_DIR/active_mission.txt")
                    mission_rom=$(echo "$mission" | cut -d'|' -f7)
                    if [ "$ROM" = "$mission_rom" ]; then
                        field_count=$(echo "$mission" | awk -F'|' '{print NF}')
                        if [ "$field_count" -lt 8 ]; then
                            mission=$(echo "$mission" | sed "s/\$/|${SESSION_DURATION}/")
                            new_total=$SESSION_DURATION
                        else
                            current_accum=$(echo "$mission" | cut -d'|' -f8)
                            new_total=$((current_accum + SESSION_DURATION))
                            mission=$(echo "$mission" | awk -F'|' -v newval="$new_total" 'BEGIN{OFS="|"} {$8=newval; print}')
                        fi
                        echo "$mission" > "$BITPAL_DIR/active_mission.txt"
                        target_seconds=$(( $(echo "$mission" | cut -d'|' -f4) * 60 ))
                        if [ "$new_total" -ge "$target_seconds" ]; then
                            finalize_mission "$BITPAL_DIR/active_mission.txt"
                        fi
                    fi
                fi
            else
                ./show_message "Game file not found|$ROM" -l a
            fi
            ;;
        "bitpal_options")
            options_output=$(./picker "bitpal_options.txt")
            options_status=$?
            [ $options_status -ne 0 ] && continue
            option_action=$(echo "$options_output" | cut -d'|' -f2)
            if [ -x "./bitpal_options/${option_action}.sh" ]; then
                export SELECTED_ITEM="$picker_output"
                export MENU
                export BITPAL_DIR
                export BITPAL_DATA
                export ACTIVE_MISSION="$BITPAL_DIR/active_mission.txt"
                export ACTIVE_MISSIONS_DIR
                export COMPLETED_FILE
                "./bitpal_options/${option_action}.sh"
            fi
            ;;
    esac
done

cleanup
exit 0
