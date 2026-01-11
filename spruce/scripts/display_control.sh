#!/bin/sh
# Display Control Script for Miyoo Mini (Spruce)
# Usage: ./display_control.sh <brightness> <saturation> <contrast> <hue> <red> <green> <blue>
#
# BRIGHTNESS (luma):   6-100   (default: 45)  - Higher = brighter screen
# SATURATION:          0-100   (default: 45)  - Higher = more vivid colors, 0 = grayscale
# CONTRAST:            0-100   (default: 50)  - Higher = more contrast, 0 = washed out
# HUE:                 0-100   (default: 50)  - Shifts color hue
# RED:                 0-255   (default: 128) - Red channel intensity
# GREEN:               0-255   (default: 128) - Green channel intensity
# BLUE:                0-255   (default: 128) - Blue channel intensity
#
# IMPORTANT NOTE: The colortemp command uses BLUE GREEN RED order (not RGB order)!
#
# Examples:
#   ./display_control.sh 60 55 55 50 128 128 128    (brighter, more vivid, neutral color)
#   ./display_control.sh 45 45 50 50 128 128 128    (restore defaults)
#   ./display_control.sh 45 45 50 50 140 105 70     (warm/blue light filter)
#   ./display_control.sh 45 45 50 50 100 128 180    (cool/blue tint)
#   ./display_control.sh 45 45 50 50 160 90 50      (very warm orange tint for night)

BRIGHTNESS=${1:-45}
SATURATION=${2:-45}
CONTRAST=${3:-50}
HUE=${4:-50}
RED=${5:-128}
GREEN=${6:-128}
BLUE=${7:-128}

echo "========================================"
echo "Setting Display Parameters:"
echo "  Brightness: $BRIGHTNESS"
echo "  Saturation: $SATURATION"
echo "  Contrast:   $CONTRAST"
echo "  Hue:        $HUE"
echo "  RGB:        R=$RED G=$GREEN B=$BLUE"
echo "========================================"

# Check if /proc/mi_modules/mi_disp/mi_disp0 exists
if [ ! -w "/proc/mi_modules/mi_disp/mi_disp0" ]; then
    echo "ERROR: Cannot write to /proc/mi_modules/mi_disp/mi_disp0"
    echo "Display control not available on this device."
    exit 1
fi

# Apply CSC settings (brightness, saturation, contrast, hue)
# Command format: csc [dev] [cscMatrix] [contrast] [hue] [luma] [saturation] [sharpness] [gain]
echo "csc 0 3 $CONTRAST $HUE $BRIGHTNESS $SATURATION 0 0" > /proc/mi_modules/mi_disp/mi_disp0

# Wait a moment between commands
usleep 100000

# Apply color temperature (RGB values)
# IMPORTANT: colortemp uses BLUE GREEN RED order (not RGB order)!
# Command format: colortemp [dev] [0] [0] [0] [blue] [green] [red]
echo "colortemp 0 0 0 0 $BLUE $GREEN $RED" > /proc/mi_modules/mi_disp/mi_disp0

echo "Done! Settings applied."
echo ""
echo "To restore defaults, run:"
echo "  ./display_control.sh 45 45 50 50 128 128 128"
