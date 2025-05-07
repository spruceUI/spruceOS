#!/bin/sh

export BITPAL_APP_DIR=/mnt/SDCARD/App/BitPal
export FACE_DIR=$BITPAL_APP_DIR/bitpal_faces

export BITPAL_DATA_DIR=/mnt/SDCARD/Saves/spruce/bitpal_data
export BITPAL_JSON=$BITPAL_DATA_DIR/bitpal.json
export MISSION_JSON=$BITPAL_DATA_DIR/active_missions.json
export COMPLETED_JSON=$BITPAL_DATA_DIR/completed_missions.json

export GTT_JSON=/mnt/SDCARD/Saves/spruce/gtt.json

# ensure later referenced json paths in this dir are valid
mkdir -p "$BITPAL_DATA_DIR"

call_menu() {
    title="$1"
    menu="$2"

    /mnt/SDCARD/spruce/flip/bin/python3 \
    /mnt/SDCARD/App/PyUI/main-ui/OptionSelectUI.py \
    "$title" /mnt/SDCARD/App/BitPal/menus/$menu
}

# resets bitpal to level 1
initialize_bitpal_data() {
    DATETIME=$(date +%s)
    jq -n --argjson datetime $DATETIME '{ bitpal: {
        name: "BitPal",
        level: 1,
        xp: 0,
        xp_next: 100,
        mood: "happy",
        last_visit: $datetime,
        missions_completed: 0
    } }' > "$BITPAL_JSON"
}

display_bitpal_stats() {
    face="$(get_face)"
    name="$(jq -r '.bitpal.name' "$BITPAL_JSON")"
    level="$(jq -r '.bitpal.level' "$BITPAL_JSON")"
    xp="$(jq -r '.bitpal.xp' "$BITPAL_JSON")"
    xp_next="$(jq -r '.bitpal.xp_next' "$BITPAL_JSON")"
    mood="$(jq -r '.bitpal.mood' "$BITPAL_JSON")"
    missions_completed="$(jq '.bitpal.missions_completed' "$BITPAL_JSON")"
    missions_active="$(jq '.missions // [] | length' "$MISSION_JSON")"

    display --okay -s 36 -p 50 -t "$name Lv.$level - Status
 
$face
 
XP: $xp/$xp_next
Mood: $mood
Missions Completed: $missions_completed
$missions_active Active Missions"
}

##### MOOD-RELATED FUNCTIONS #####

get_face() {
   case "$mood" in
       excited)   echo "[^o^]" ;;
       happy)     echo "[^-^]" ;;
       neutral)   echo "[-_-]" ;;
       sad)       echo "[;_;]" ;;
       angry)     echo "[>_<]" ;;
       surprised) echo "[O_O]" ;;
       *)         echo "[^-^]" ;;
   esac
}

set_random_good_mood() {
    mood_num=$((random % 2))
    case $mood_num in
        0) export mood="excited" ;;
        1) export mood="happy" ;;
    esac
}

set_random_okay_mood() {
    mood_num=$((random % 2))
    case $mood_num in
        0) export mood="neutral" ;;
        1) export mood="surprised" ;;
    esac
}

set_random_negative_mood() {
    mood_num=$((random % 3))
    case $mood_num in
        0) export mood="sad" ;;
        1) export mood="angry" ;;
        2) export mood="surprised" ;;
    esac
}

update_mood() {
    tmpfile=$(mktemp)
    jq --arg mood $mood '.bitpal += { mood: $mood }' \
    "$BITPAL_JSON" > "$tmpfile" && mv "$tmpfile" "$BITPAL_JSON"
}

##### RANDOM MESSAGES #####

get_random_greeting() {
    greeting_num=$((RANDOM % 20))
    face=$(get_face)
    case $greeting_num in
        0) echo "$face
 
 Hello, gamer! Ready to level up?" ;;
        1) echo "$face
 
 Welcome back, hero! Adventure awaits!" ;;
        2) echo "$face
 
 It's dangerous to go alone! Take BitPal!" ;;
        3) echo "$face
 
 Hi there! Your high score quest continues!" ;;
        4) echo "$face
 
 Power up! Grab that mushroom!" ;;
        5) echo "$face
 
 Hey, champion! Ready to beat the final boss?" ;;
        6) echo "$face
 
 HADOUKEN! Let's get gaming!" ;;
        7) echo "$face
 
 Good to see you! Extra lives collected!" ;;
        8) echo "$face
 
 Insert coin to continue? The arcade is calling!" ;;
        9) echo "$face
 
 Welcome back, legend! A new challenger appears!" ;;
        10) echo "$face
 
 Game time! BitPal has entered the game!" ;;
        11) echo "$face
 
 Konami Code activated! Gaming powers unlocked!" ;;
        12) echo "$face
 
 Player One detected! Press START!" ;;
        13) echo "$face
 
 Waka Waka Waka! Time to play!" ;;
        14) echo "$face
 
 Game cartridge inserted! Blow on it first!" ;;
        15) echo "$face
 
 Coins inserted! No lag detected!" ;;
        16) echo "$face
 
 New high score potential detected! Let's go!" ;;
        17) echo "$face
 
 Controller connected! Ready to rumble!" ;;
        18) echo "$face
 
 Pixels powered up! 8-bit mode activated!" ;;
        19) echo "$face
 
 FINISH HIM! ...I mean, let's play some games!" ;;
    esac
}

get_random_fact() {
    fact_num=$((RANDOM % 84 + 1))
    case $fact_num in
        1) echo "The Nintendo Game Boy was released in 1989 and sold over 118 million units!" ;;
        2) echo "The Atari 2600 was the first widely successful home console with over 30 million sold." ;;
        3) echo "Super Mario Bros. was created by Shigeru Miyamoto and released for the NES in 1985." ;;
        4) echo "Tetris was created in 1984 by Russian engineer Alexey Pajitnov." ;;
        5) echo "The first video game console, the Magnavox Odyssey, was released in 1972." ;;
        6) echo "The highest-grossing arcade game of all time is Pac-Man, released in 1980." ;;
        7) echo "The Game Boy's most popular game, Tetris, sold over 35 million copies!" ;;
        8) echo "Pong, released by Atari in 1972, was the first commercially successful video game." ;;
        9) echo "The term 'Easter egg' for hidden game content comes from Adventure on the Atari 2600." ;;
        10) echo "You must earn 2,700 XP to reach tenlevels in BitPal" ;;
        11) echo "Sonic the Hedgehog was created to give SEGA a mascot to compete with Mario." ;;
        12) echo "The Legend of Zelda was inspired by creator Miyamoto's childhood explorations in the countryside." ;;
        13) echo "The PlayStation was originally going to be a Nintendo CD add-on until the deal fell through." ;;
        14) echo "Pac-Man's design was inspired by a pizza with a slice removed, according to its creator." ;;
        15) echo "The name 'SEGA' is an abbreviation of 'Service Games,' its original company name." ;;
        16) echo "The Legend of Zelda was the first console game that allowed players to save their progress without passwords!" ;;
        17) echo "Mortal Kombat's blood code 'ABACABB' on Genesis is a reference to the band Genesis's album 'Abacab'!" ;;
        18) echo "The term 'Easter egg' for hidden game content comes from Adventure on the Atari 2600." ;;
        19) echo "The Konami Code (UUDDLRLRBA) first appeared in Gradius for the NES in 1986." ;;
        20) echo "GoldenEye 007 for N64 was developed by only 9 people, most as their first game." ;;
        21) echo "Space Invaders was so popular in Japan that it caused a temporary coin shortage!" ;;
        22) echo "The Game & Watch's dual screen design later inspired the Nintendo DS." ;;
        23) echo "The entire Doom engine was written by John Carmack while secluded in a cabin in the mountains for 6 weeks!" ;;
        24) echo "Mario was originally called 'Jumpman' in the arcade game Donkey Kong." ;;
        25) echo "The Neo Geo home console cost 650 usd in 1990, equivalent to over 1,400 usd in today's money!" ;;
        26) echo "The NES Zapper doesn't work on modern TVs due to their different refresh rates." ;;
        27) echo "E.T. for Atari 2600 flopped so badly that thousands of cartridges were buried in a landfill." ;;
        28) echo "The term 'boss fight' comes from a mistranslation of the Japanese word for 'master.'" ;;
        29) echo "The PlayStation controller's symbols have meanings: circle (yes), cross (no), triangle (viewpoint), square (menu)." ;;
        30) echo "The Game Boy survived a bombing during the Gulf War and still works at Nintendo NY!" ;;
        31) echo "The first Easter egg in a video game was developer Warren Robinett hiding his name in Adventure (1979)." ;;
        32) echo "The SNES's rounded corners were designed to prevent parents from putting drinks on top of it." ;;
        33) echo "Street Fighter II's combos were actually a glitch that developers decided to keep in the game." ;;
        34) echo "Donkey Kong was almost named 'Monkey Kong' but got mistranslated during development." ;;
        35) echo "Final Fantasy was so named because creator Hironobu Sakaguchi thought it would be his last game." ;;
        36) echo "In the original Pokemon Red/Blue, Missingno wasn't a glitch but a deliberate debug placeholder Nintendo forgot!" ;;
        37) echo "The Turbografx-16 was actually an 8-bit console, despite what its name suggests." ;;
        38) echo "The Atari 2600 joystick was designed to survive being thrown against a wall in frustration." ;;
        39) echo "The original Metal Gear was released on the MSX2 computer in 1987, not the NES version most know." ;;
        40) echo "Keith Courage in Alpha Zones was a TurboGrafx-16 launch title where Keith transforms into a mecha warrior!" ;;
        41) echo "Bubble Bobble has 100 levels and a special ending only shown when two players complete it together." ;;
        42) echo "The original Mortal Kombat arcade cabinet used 8 megabytes of graphics data, which was huge for 1992." ;;
        43) echo "The Vectrex console from 1982 came with its own built-in vector display screen!" ;;
        44) echo "In Pac-Man, each ghost has a unique personality and hunting style programmed into its AI." ;;
        45) echo "The Virtual Boy, Nintendo's 1995 3D console, is considered one of their rare commercial failures." ;;
        46) echo "Super Mario 64 was the first game where Mario could triple jump, wall jump, and ground pound." ;;
        47) echo "The SNES had a secret 'Sound Test' menu that could only be accessed with a special music studio cartridge!" ;;
        48) echo "Contra's famous 30-life code was originally created by developers for testing but accidentally left in!" ;;
        49) echo "The NES version of Contra was actually censored - the original arcade enemies were human soldiers!" ;;
        50) echo "The PlayStation memory card could store 15 save files across multiple games." ;;
        51) echo "The Atari Jaguar was marketed as the first 64-bit console, but actually combined two 32-bit CPUs." ;;
        52) echo "Nintendo's first electronic game was the 1975 Laser Clay Shooting System, a skeet shooting simulator." ;;
        53) echo "The Famicom (Japanese NES) had a built-in microphone on the second controller for certain games." ;;
        54) echo "Polybius is a mythical arcade game that supposedly caused psychoactive effects but never actually existed." ;;
        55) echo "Sega Channel, launched in 1994, was a cable service that let users download Genesis games via cable TV." ;;
        56) echo "Nintendo patented the D-pad in 1985, forcing competitors to create alternative directional controls." ;;
        57) echo "Action 52 for the NES cost 199 usd and contained 52 games, most of which were unplayable due to glitches." ;;
        58) echo "The first home video game console, the Odyssey, used plastic overlays on the TV screen instead of graphics." ;;
        59) echo "Galaga's iconic 'dual ship' feature was originally a programming bug that developers turned into a feature." ;;
        60) echo "The inventor of the Game Boy, Gunpei Yokoi, started at Nintendo fixing assembly line machines." ;;
        61) echo "Castlevania's iconic whip was originally going to be a gun until the team switched to a horror theme." ;;
        62) echo "Some arcade game PCBs contain suicide batteries that erase the ROM if removed, preventing copying." ;;
        63) echo "The Apple Pippin console was Steve Jobs' first failed attempt at entering the gaming market." ;;
        64) echo "Early SNES development kits were actually modified NES systems with special cartridges." ;;
        65) echo "The 'invincibility star' in Mario was created because designer Miyamoto loved listening to music." ;;
        66) echo "The original Zelda cartridge is gold colored because Miyamoto wanted it to look like buried treasure." ;;
        67) echo "The Game Boy was so durable that one survived a bombing in the Gulf War and still works at Nintendo's NY store!" ;;
        68) echo "The 3DO console required developers to pay just 3 usd in royalties, compared to Nintendo's 10 usd per game." ;;
        69) echo "The very first Game & Watch device, Ball, was inspired by a businessman Yokoi saw playing with a calculator." ;;
        70) echo "The Power Glove's technology was later used in medical devices and virtual reality equipment." ;;
        71) echo "Earthbound (Mother 2) cost over 200,000 usd to translate to English, an enormous sum in 1995." ;;
        72) echo "The Pioneer LaserActive could play both Sega Genesis and TurboGrafx-16 games with special modules." ;;
        73) echo "Tengen, an Atari subsidiary, bypassed Nintendo's security to release unlicensed NES games with black cartridges." ;;
        74) echo "In Karateka (1984), if you approach the princess in fighting stance, she knocks you out and the game ends." ;;
        75) echo "The Gameboy printer used thermal paper to print screenshots from games like Pokemon and Zelda." ;;
        76) echo "R.O.B. (Robotic Operating Buddy) was created to help sell the NES as a toy rather than a video game." ;;
        77) echo "Sonic was originally a rabbit who could grab objects with extendable ears before becoming a hedgehog." ;;
        78) echo "Duck Hunt's light gun success helped save the early NES when many retailers were skeptical." ;;
        79) echo "Nintendo was founded in 1889 as a playing card company before moving to video games." ;;
        80) echo "The Sega Nomad could play Genesis cartridges on the go but ate six AA batteries in about 2 hours." ;;
        81) echo "Chrono Trigger's dream team dev squad included creators from Final Fantasy and Dragon Quest." ;;
        82) echo "Tamagotchi virtual pets were banned in many schools in the 90s for being too distracting to students." ;;
        83) echo "The NES Power Pad exercise mat was originally developed by Bandai as the 'Family Trainer' in Japan." ;;
        84) echo "The year 1984 saw the release of Tetris, one of the most enduring and addictive puzzlers of all time!" ;;
    esac
}

get_random_guilt_trip() {
    face=$(get_face)
    guilt_trip=$((RANDOM % 20))
    case $guilt_trip in
        0) echo "$face
 
 Don't quit now! You haven't saved your progress! Princess is in another castle!" ;;
        1) echo "$face
 
 GAME OVER? NOT YET! Insert coin to continue? One more level awaits!" ;;
        2) echo "$face
 
 Keep your quarters ready! BitPal needs a Player 1. Just one more game?" ;;
        3) echo "$face
 
 Boss battle is loading! You can't pause now! Ready your power-ups?" ;;
        4) echo "$face
 
 EXIT? WAIT A MINUTE! You're so close to high score. One more try?" ;;
        5) echo "$face
 
 No Konami Code for exit! You must defeat Sheng Long to stand a chance!" ;;
        6) echo "$face
 
 You still have 1UP left! Hidden stages await. Will you continue?" ;;
        7) echo "$face
 
 Your star power is fading! BitPal needs your help. Save the 8-bit kingdom?" ;;
        8) echo "$face
 
 PAUSE NOT AVAILABLE! The final dungeon awaits. Stay for treasure?" ;;
        9) echo "$face
 
 Achievement unlocked: \"Almost quit BitPal\" Want to earn more?" ;;
        10) echo "$face
 
 LEVEL 99 NOT REACHED! Are you sure you want to abandon your quest?" ;;
        11) echo "$face
 
 FATALITY: BitPal sadness! BitPal is counting on you. FINISH THE GAME!" ;;
        12) echo "$face
 
 NO SAVE POINTS HERE! Your progress will be lost. Continue adventure?" ;;
        13) echo "$face
 
 PRESS START TO PLAY! Secret bosses await. Controller disconnected?" ;;
        14) echo "$face
 
 THIS ISN'T GAME OVER! The water level is next. Brave enough to stay?" ;;
        15) echo "$face
 
 RAGE QUIT DETECTED! Have you tried the Konami Code? UUDDLRLRBA?" ;;
        16) echo "$face
 
 CREDITS NOT EARNED YET! True ending requires 100% completion!" ;;
        17) echo "$face
 
 CHEAT ACTIVATED: Fun mode! Your high score is climbing. Leave the arcade now?" ;;
        18) echo "$face
 
 1UP ACQUIRED! BitPal needs you to defeat the final boss!" ;;
        19) echo "$face
 
 EXIT? THINK AGAIN! All your base are belong to us! You have no chance to survive!" ;;
    esac
}

get_random_thanks() {
    thanks_num=$((RANDOM % 6))
    case $thanks_num in
        0) echo "Phew! ... I thought I'd be alone! Thanks for sticking with me!" ;;
        1) echo "You stayed! BitPal is so relieved! Let's keep adventuring!" ;;
        2) echo "Yes! That was close... I almost lost my player!" ;;
        3) echo "Alright! Team BitPal is back and stronger than ever!" ;;
        4) echo "Woohoo! The quest continues! Thanks for not leaving me behind." ;;
        5) echo "Hurray! We're still in the game! Thank you for staying, hero!" ;;
    esac
}


##### OTHER RANDOMNESS FUNCTIONS #####

get_random_system() {

    # first get ALL systems with a Roms subdir
    ROMS_DIR="/mnt/SDCARD/Roms"
    systems_list=""
    for d in "$ROMS_DIR"/*; do
        [ -d "$d" ] && systems_list="${systems_list}$d "
    done

    # next filter by whether they have Roms
    systems_with_roms=""
    count=0
    for d in $systems_list; do
        has_roms="false"
        for file in "$d"/*; do
            file="$(basename $file)"
            case "$file" in
                Imgs|imgs|IMGS|IMGs|*.db|*.json|*.txt|*.xml|.gitkeep) continue ;;
                *) has_roms="true"; count=$((count + 1)); break ;;
            esac
        done
        if [ "$has_roms" = "true" ]; then
            systems_with_roms="${systems_with_roms}$d\n"
        fi
    done

    # now pick and echo a random one of those non-empty romdirs
    random_system="$(echo -e "$systems_with_roms" | sed -n "$((RANDOM % count + 1))p")"
    random_system="$(basename $random_system)"
    echo "$random_system"
}

is_valid_rom() {
    local file="$1"
    if echo "$file" | grep -qiE '\.png$'; then
        folder=$(dirname "$file")
        if echo "$folder" | grep -Eiq "pico|fake"; then
            return 0
        fi
    fi
    if echo "$file" | grep -qiE '\.(txt|log|cfg|ini|gitkeep)$'; then
        return 1
    fi
    if echo "$file" | grep -qiE '\.(jpg|jpeg|png|bmp|gif|tiff|webp)$'; then
        return 1
    fi
    if echo "$file" | grep -qiE '\.(xml|json|md|html|css|js|map)$'; then
        return 1
    fi
    return 0
}

get_random_game() {
    ROMS_DIR=/mnt/SDCARD/Roms
    console="$1"

    roms_list=""
    count=0
    for f in "$ROMS_DIR/$console"/*; do
        if [ -f "$f" ] && is_valid_rom "$f"; then
            roms_list="${roms_list}$f\n"
            count=$((count + 1))
        fi
    done
    if [ $count -eq 0 ]; then echo ""; return 1; fi
    random_rom=$(echo -e "$roms_list" | sed -n "$((RANDOM % count + 1))p")
    echo "$random_rom"
}

##### MISSION MANAGEMENT #####

# creates or overwrites active missions file with blank copy
initialize_mission_data() {
    jq -n '{ missions: {} }' > "$MISSION_JSON"
}

generate_random_mission() {

    # index for which mission slot to use
    i="$1"
    tmpfile=/tmp/new_mission$i

    # randomly choose which mission type to generate
    type_num=$((RANDOM % 5))
    case $type_num in
        0) type=surprise ;;
        1) type=discover ;;
        2) type=rediscover ;;
        3) type=system ;;
        4) type=any ;;
    esac

    # random duration between 5 and 25 minutes
    duration=$((RANDOM % 15 + 10))

    # if nothing in GTT json yet, don't give rediscover missions
    if [ ! -f "$GTT_JSON" ] || grep -q "games: {}" "$GTT_JSON"; then
        if [ "$type" = "rediscover" ]; then
            type=discover
        fi
    fi

    case "$type" in
        surprise)
            console="$(get_random_system)"
            rompath="$(get_random_game "$console")"
            game="$(basename "${rompath%.*}") ($console)"
            mult=8
            display_text="SURPRISE GAME!"
            ;;
        discover)
            console="$(get_random_system)"
            rompath="$(get_random_game "$console")"
            game="$(basename "${rompath%.*}") ($console)"
            mult=7
            display_text="Try out $game for the first time!"
            ;;
        rediscover)
            console="$(get_random_system)"
            # need to change to only get random game from GTT json
            rompath="$(get_random_game "$console")"
            game="$(basename "${rompath%.*}") ($console)"
            mult=7
            display_text="Rediscover $game!"
            ;;
        system)
            console="$(get_random_system)"
            unset rompath
            unset game
            mult=6
            display_text="Play a $console game!"
            ;;
        any) 
            unset console
            unset rompath
            unset game
            mult=5
            display_text="Play any game you want!"
            ;;
    esac

    # calculate xp reward
    xp_reward=$((mult * duration))

    # construct temp file to hold unconfirmed mission info
    echo "export type=$type" > "$tmpfile"
    echo "export display_text=\"$display_text\"" >> "$tmpfile"
    echo "export rompath=\"$rompath\"" >> "$tmpfile"
    echo "export game=\"$game\"" >> "$tmpfile"
    echo "export console=$console" >> "$tmpfile"
    echo "export duration=$duration" >> "$tmpfile"
    echo "export xp_reward=$xp_reward" >> "$tmpfile"
}

generate_3_missions() {
    generate_random_mission 1
    generate_random_mission 2
    generate_random_mission 3
}

construct_new_mission_menu() {
    MISSION_MENU=/mnt/SDCARD/App/BitPal/menus/new_mission.json
    rm -f "$MISSION_MENU" 2>/dev/null

    . /tmp/new_mission1
    display_text_1="$display_text"
    . /tmp/new_mission2
    display_text_2="$display_text"
    . /tmp/new_mission3
    display_text_3="$display_text"

    echo "[" > "$MISSION_MENU"
    echo "  {" >> "$MISSION_MENU"
    echo "    \"primary_text\": \"$display_text_1\"," >> "$MISSION_MENU"
    echo "    \"value\": \"/mnt/SDCARD/App/BitPal/menus/main.sh accept 1\"" >> "$MISSION_MENU"
    echo "  }," >> "$MISSION_MENU"
    echo "  {" >> "$MISSION_MENU"
    echo "    \"primary_text\": \"$display_text_2\"," >> "$MISSION_MENU"
    echo "    \"value\": \"/mnt/SDCARD/App/BitPal/menus/main.sh accept 2\"" >> "$MISSION_MENU"
    echo "  }," >> "$MISSION_MENU"
    echo "  {" >> "$MISSION_MENU"
    echo "    \"primary_text\": \"$display_text_3\"," >> "$MISSION_MENU"
    echo "    \"value\": \"/mnt/SDCARD/App/BitPal/menus/main.sh accept 3\"" >> "$MISSION_MENU"
    echo "  }" >> "$MISSION_MENU"
    echo "]" >> "$MISSION_MENU"
}

construct_manage_mission_menu() {
    MANAGE_MENU=/mnt/SDCARD/App/BitPal/menus/manage_missions.json
    tmpfile="$(mktemp)"
    echo "[]" > "$tmpfile"
    for mission in 1 2 3 4 5; do
        if mission_exists "$mission"; then
            primary_text="$mission) $(jq -r ".missions[\"$mission\"].display_text" "$MISSION_JSON")"
            value="/mnt/SDCARD/App/BitPal/menus/main.sh view_mission $mission"
            jq --arg primary_text "$primary_text" \
               --arg value "$value" \
                '. += [{ 
                    primary_text: $primary_text,
                    image_path: "", 
                    image_path_selected: "", 
                    value: $value 
                }]' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        fi
    done
    mv "$tmpfile" "$MANAGE_MENU"
}

accept_mission() {
    selected_mission="$1"
    . "$selected_mission"

    for i in 1 2 3 4 5; do
        if mission_exists "$i"; then
            continue
        else
            index="$i"
            break
        fi
    done

    case "$type" in
        discover|rediscover|surprise)
            add_mission_to_active_json "$index" \
            "$type" "$display_text" "$game" "$console" \
            "$rompath" "$duration" "$xp_reward"
            ;;
        system)
            select_game_from_system
            ;;
        any)
            select_system
            ;;
    esac
}

mission_exists() {
    index="$1"
    [ ! -f "$MISSION_JSON" ] && return 1
    jq -e --arg index "$index" '.missions[$index] != null' "$MISSION_JSON" >/dev/null
}

missions_full() {
    num_missions=0
    for i in 1 2 3 4 5; do
        if mission_exists "$i"; then
            num_missions=$((num_missions+1))
        fi
    done
    if [ "$num_missions" -ge 5 ]; then
        return 0
    else
        return 1
    fi
}

missions_empty() {
    num_missions=0
    for i in 1 2 3 4 5; do
        if mission_exists "$i"; then
            num_missions=$((num_missions+1))
        fi
    done
    if [ "$num_missions" -le 0 ]; then
        return 0
    else
        return 1
    fi  
}

# adds a mission with the specified details to your active missions file
# example:
# add_mission_to_active_json 1 surprise "SURPRISE GAME!" "Adventure Island (GB)" "GB" "/mnt/SDCARD/Roms/GB/Adventure Island.zip" 10 80
add_mission_to_active_json() {
    tmpfile=$(mktemp)
    [ ! -f "$MISSION_JSON" ] && initialize_mission_data

    jq --arg index "$1" \
    --arg type "$2" \
    --arg display_text "$3" \
    --arg game "$4" \
    --arg console "$5" \
    --arg rompath "$6" \
    --arg duration "$7" \
    --arg xp_reward "$8" \
    --arg startdate "$(date +%s)" \
    '.missions[$index] = {
            type: $type,
            display_text: $display_text,
            game: $game,
            console: $console,
            rompath: $rompath,
            duration: ($duration|tonumber),
            xp_reward: ($xp_reward|tonumber),
            startdate: ($startdate|tonumber),
            time_spent: 0,
            enddate: 0
    }' "$MISSION_JSON" > "$tmpfile" && mv "$tmpfile" "$MISSION_JSON"
}

# moves a mission out of active missions and into completed missions
move_mission_to_completed_json() {
    INDEX="$1"

    [ ! -f "$MISSION_JSON" ] && initialize_mission_data
    [ ! -f "$COMPLETED_JSON" ] && echo "[]" > "$COMPLETED_JSON"

    # Extract mission from active_missions
    MISSION=$(jq --argjson i "$INDEX" '.missions[$i]' "$MISSION_JSON")

    # Remove it from active_missions.json
    tmpfile=$(mktemp)
    jq --argjson i "$INDEX" 'del(.missions[$i])' "$MISSION_JSON" > "$tmpfile" && mv "$tmpfile" "$MISSION_JSON"

    # Append mission to completed_missions.json
    tmpfile=$(mktemp)
    echo "$MISSION"   jq --slurpfile m /dev/stdin '. += $m' "$COMPLETED_JSON" > "$tmpfile" && mv "$tmpfile" "$COMPLETED_JSON"
}