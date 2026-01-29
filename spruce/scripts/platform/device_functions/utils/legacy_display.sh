#!/bin/sh

# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    kill -9 $(pgrep display) 2> /dev/null
}

# Call this to display text on the screen
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL display_kill()
# It's possible to leave a display process running
# Usage: display [options]
# Options:
#   -i, --image <path>    Image path (default: DEFAULT_IMAGE)
#   -t, --text <text>     Text to display
#   -d, --delay <seconds> Delay in seconds (default: 0)
#   -s, --size <size>     Text size (default: 36)
#   -p, --position <pos>  Text position as percentage from the top of the screen
#   (Text is offset from it's center, images are offset from the top of the image)
#   -a, --align <align>   Text alignment (left, middle, right) (default: middle)
#   -w, --width <width>   Text width (default: 600)
#   -c, --color <color>   Text color in RGB format (default: dbcda7) Spruce text yellow
#   -f, --font <path>     Font path (optional)
#   -o, --okay            Use ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE and runs acknowledge()
#   -bg, --bg-color <color> Background color in RGB format (default: 7f7f7f)
#   -bga, --bg-alpha <alpha> Background alpha value (0-255, default: 0)
#   -is, --image-scaling <scale> Image scaling factor (default: 1.0)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000
# Calling display with -o/--okay will use the ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE
# Calling display with --confirm will use the CONFIRM_IMAGE instead of DEFAULT_IMAGE
# If using --confirm, you should call the confirm() message in an if block in your script
# --confirm will supercede -o/--okay
# You can also call infinite image layers with (next-image.png scale height side)*
#   --icon <path>         Path to an icon image to display on top (default: none)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000 --icon "/path/to/icon.png"

display() {
    [ "$DISPLAY_ASPECT_RATIO" = "16:9" ] && DEFAULT_IMAGE="/mnt/SDCARD/spruce/imgs/displayTextWidescreen.png" || DEFAULT_IMAGE="/mnt/SDCARD/spruce/imgs/displayText.png"

    ACKNOWLEDGE_IMAGE="/mnt/SDCARD/spruce/imgs/displayAcknowledge.png"
    CONFIRM_IMAGE="/mnt/SDCARD/spruce/imgs/displayConfirm.png"
    DEFAULT_FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"

    width="$DISPLAY_TEXT_ELF_WIDTH" # from ${PLATFORM}.cfg
    image="$DEFAULT_IMAGE" text=" " delay=0 size=30 position=50 align="middle" color="ebdbb2" font=""
    use_acknowledge_image=false
    use_confirm_image=false
    run_acknowledge=false
    bg_color="7f7f7f" bg_alpha=0 image_scaling=1.0
    icon_image=""
    additional_images=""
    position_set=false
    qr_url=""

    while [ $# -gt 0 ]; do
        case $1 in
            -i|--image) image="$2"; shift ;;
            -t|--text) text="$2"; shift ;;
            -d|--delay) delay="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -p|--position) position="$2"; position_set=true; shift ;;
            -a|--align) align="$2"; shift ;;
            -w|--width) width="$2"; shift ;;
            -c|--color) color="$2"; shift ;;
            -f|--font) font="$2"; shift ;;
            -o|--okay) use_acknowledge_image=true; run_acknowledge=true ;;
            --confirm) use_confirm_image=true; use_acknowledge_image=false; run_acknowledge=false ;;
            -bg|--bg-color) bg_color="$2"; shift ;;
            -bga|--bg-alpha) bg_alpha="$2"; shift ;;
            -is|--image-scaling) image_scaling="$2"; shift ;;
            --icon)
                icon_image="$2"
                if [ "$position_set" = false ]; then
                    position=80
                fi
                shift
                ;;
            --add-image)
                additional_images="$additional_images \"$2\" $3 $4 $5"
                shift 4
                ;;
            --qr)
                qr_url="$2"
                if [ "$position_set" = false ]; then
                    position=89
                fi
                shift
                ;;
            *) log_message "Unknown option: $1"; return 1 ;;
        esac
        shift
    done
    r=$(echo "$color" | cut -c1-2)
    g=$(echo "$color" | cut -c3-4)
    b=$(echo "$color" | cut -c5-6)
    bg_r=$(echo "$bg_color" | cut -c1-2)
    bg_g=$(echo "$bg_color" | cut -c3-4)
    bg_b=$(echo "$bg_color" | cut -c5-6)

    # Set font to DEFAULT_FONT if it's empty
    if [ -z "$font" ]; then
        font="$DEFAULT_FONT"
    fi

    command="LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" display_text.elf "
    command="$command""$DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION "

    # Construct the command
    command="$command""\"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

    # Add icon image if specified
    if [ -n "$icon_image" ]; then
        command="$command \"$icon_image\" 0.20 center middle"
    fi

    # Add CONFIRM_IMAGE if --confirm flag is used, otherwise use ACKNOWLEDGE_IMAGE if --okay flag is used
    if [ "$use_confirm_image" = true ]; then
        command="$command \"$CONFIRM_IMAGE\" 1.0 240 middle"
        delay=0
    elif [ "$use_acknowledge_image" = true ]; then
        command="$command \"$ACKNOWLEDGE_IMAGE\" 1.0 240 middle"
    fi

    # Add additional images
    if [ -n "$additional_images" ]; then
        command="$command $additional_images"
    fi

    # Generate QR code if --qr flag is used
    if [ -n "$qr_url" ]; then
        qr_image=$(qr_code -t "$qr_url")
        if [ -n "$qr_image" ]; then
            command="$command \"$qr_image\" 0.50 top middle"
        else
            log_message "Failed to generate QR code for URL: $qr_url" -v
        fi
    fi

    display_kill

    # Execute the command in the background if delay is 0
    if [ "$delay" -eq 0 ]; then
        eval "$command" &
        log_message "display command: $command"
        # Run acknowledge if -o or --okay was used and --confirm was not used
        if [ "$run_acknowledge" = true ] && [ "$use_confirm_image" = false ]; then
            acknowledge
        fi
    else
        # Execute the command and capture its output
        eval "$command"
        log_message "display command: $command"
    fi
}
