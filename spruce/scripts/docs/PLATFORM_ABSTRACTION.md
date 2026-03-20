# Platform Abstraction Layer Documentation

This document describes how SpruceOS achieves device-agnostic script design through hardware abstraction, allowing the same scripts to run on all supported handheld devices with minimal changes.

## Table of Contents

1. [Platform Detection](#platform-detection)
2. [Architecture Overview](#architecture-overview)
3. [Platform Configuration Files](#platform-configuration-files)
4. [Device-Specific Functions](#device-specific-functions)
5. [Implementation Examples](#implementation-examples)
6. [Adding Support for New Devices](#adding-support-for-new-devices)

## Platform Detection

### Device Identification

Device detection happens automatically when `helperFunctions.sh` is sourced. The detection reads `/proc/cpuinfo` and classifies devices based on CPU model:

```bash
# Device Detection Logic (in helperFunctions.sh)

if grep -q "sun8i" /proc/cpuinfo; then
    PLATFORM="A30"
    BRAND="Miyoo"
elif grep -q "TG5040" /proc/cpuinfo; then
    PLATFORM="SmartPro"
    BRAND="TrimUI"
elif grep -q "TG3040" /proc/cpuinfo; then
    PLATFORM="Brick"
    BRAND="TrimUI"
elif grep -q "TG5050" /proc/cpuinfo; then
    PLATFORM="SmartProS"
    BRAND="TrimUI"
elif grep -q "0xd05" /proc/cpuinfo; then
    PLATFORM="Flip"
    BRAND="Miyoo"
elif grep -q "0xd04" /proc/cpuinfo; then
    PLATFORM="Pixel2"
    BRAND="Miyoo"
else
    PLATFORM="MiyooMini"  # Default
    BRAND="Miyoo"
fi
```

### Architecture Detection

After device identification, architecture is determined:

```bash
if [ -n "$(file /bin/bash | grep 'ARM')" ]; then
    if [ -n "$(file /bin/bash | grep '32-bit')" ]; then
        PLATFORM_ARCHITECTURE="armhf"      # 32-bit
    else
        PLATFORM_ARCHITECTURE="aarch64"    # 64-bit
    fi
fi
```

**Architecture Grouping:**

- **32-bit (armhf):** A30, MiyooMini
- **64-bit (aarch64):** Flip, SmartPro, SmartProS, Pixel2, Brick

## Architecture Overview

### Three-Layer Abstraction Model

```
┌─────────────────────────────────────────────────────┐
│  Application Scripts (runtime.sh, principal.sh, etc) │
│        - Device-agnostic application logic          │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│      Platform Abstraction Layer (helperFunctions)   │
│  - Generic helper functions                         │
│  - Device detection logic                           │
│  - Configuration access via get_config_value()      │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│   Device-Specific Implementation Layer               │
│  (platform/device_functions/*.sh)                   │
│  - CPU control (set_performance, set_powersave)     │
│  - Display/brightness control                       │
│  - LED control (TrimUI only)                        │
│  - Hardware initialization                          │
│  - Vibration/rumble control                         │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│            Hardware/OS Layer                        │
│  - Linux sysfs (/sys/class/*)                       │
│  - Device nodes (/dev/input/*)                      │
│  - ALSA audio (/dev/snd/*)                          │
└─────────────────────────────────────────────────────┘
```

### Sourcing Pattern

Most scripts follow this sourcing pattern to leverage abstraction:

```bash
#!/bin/bash

# 1. Source core helpers (loads device detection)
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# Now $PLATFORM and $SYSTEM_JSON are available

# 2. Load platform-specific device functions
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# 3. Use unified interface (automatically routed)
set_performance     # Calls A30-specific or Flip-specific code
vibrate             # Route-dependent implementation
rgb_led "red"       # Works on TrimUI, logged as unsupported on Miyoo

# 4. Use generic helpers
get_config_value '.menuOptions.System.swapfileSize.selected'
```

## Platform Configuration Files

### Configuration File Location and Structure

```
platform/
├── A30.cfg              # Miyoo A30 (32-bit)
├── MiyooMini.cfg        # Miyoo Mini (32-bit)
├── Flip.cfg             # Miyoo Flip (64-bit)
├── SmartPro.cfg         # TrimUI SmartPro (64-bit)
├── SmartProS.cfg        # TrimUI SmartProS (64-bit)
├── Pixel2.cfg           # Miyoo Pixel2 (64-bit)
├── Brick.cfg            # TrimUI Brick (64-bit)
└── device.sh            # Device detection helper
```

### Configuration File Format

Each `.cfg` file defines hardware-specific paths and button mappings in shell variable format:

```bash
# platform/A30.cfg
# Miyoo A30 Hardware Configuration
# CPU: Allwinner H2+ (sun8i), 1.2GHz quad-core ARM Cortex-A7, 32-bit
# Display: 3.5" 320×240, IPS LCD
# RAM: 512MB

# Input Event Paths
export EVENT_PATH_BUTTONS="/dev/input/event3"
export EVENT_PATH_POWER="/dev/input/event0"
export EVENT_PATH_JOYSTICK="/dev/input/event4"
export EVENT_PATH_BRIGHTNESS="/dev/input/event5"

# Button Key Codes
export B_A=305
export B_B=304
export B_X=308
export B_Y=307
export B_L1=310
export B_L2=312
export B_R1=311
export B_R2=313
export B_UP=103
export B_DOWN=108
export B_LEFT=105
export B_RIGHT=106
export B_START=28
export B_SELECT=1
export B_MENU=274
export B_POWER=116

# Display Paths
export DEVICE_BRIGHTNESS_PATH="/sys/class/backlight/*/brightness"
export BRIGHTNESS_MAX=255
export BRIGHTNESS_MIN=0

# System Brightness Levels (11 levels for UI)
export SYSTEM_BRIGHTNESS_0=0
export SYSTEM_BRIGHTNESS_1=23
export SYSTEM_BRIGHTNESS_2=46
export SYSTEM_BRIGHTNESS_3=69
export SYSTEM_BRIGHTNESS_4=92
export SYSTEM_BRIGHTNESS_5=115
export SYSTEM_BRIGHTNESS_6=138
export SYSTEM_BRIGHTNESS_7=161
export SYSTEM_BRIGHTNESS_8=184
export SYSTEM_BRIGHTNESS_9=207
export SYSTEM_BRIGHTNESS_10=255

# CPU Paths
export CPUFREQ_PATH="/sys/devices/system/cpu/cpu0/cpufreq/"
export CPUGOV_PATH="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

# Battery Paths
export BATTERY_PATH="/sys/class/power_supply/battery/"
export BATTERY_CAPACITY="${BATTERY_PATH}capacity"

# Audio
export DEVICE_AUDIO_OUTPUT="/dev/snd/pcmC1D0p"
export DEVICE_AUDIO_CONTROL="/dev/snd/controlC1"

# Vibration (GPIO-based)
export VIBRATION_PATH="/sys/class/gpio/gpio48"

# Display Aspect Ratio
export DISPLAY_ASPECT_RATIO="16:9"
```

### Configuration for TrimUI SmartPro (with RGB LEDs)

```bash
# platform/SmartPro.cfg
# RGB LED paths (TrimUI-specific)
export LED_PATH="/sys/class/leds/"
export LED_LEFT="${LED_PATH}led_left/brightness"
export LED_RIGHT="${LED_PATH}led_right/brightness"
export LED_MIDDLE="${LED_PATH}led_middle/brightness"
export LED_1="${LED_PATH}led1/brightness"
export LED_2="${LED_PATH}led2/brightness"

# TrimUI-specific CPU/GPU
export GPU_FREQ_PATH="/sys/class/devfreq/ff9a0000.gpu/"
export THERMAL_CORE="/sys/class/thermal/thermal_zone0/"
```

## Device-Specific Functions

### File Organization

```
platform/device_functions/
├── A30.sh              # A30-specific implementations
├── MiyooMini.sh        # MiyooMini-specific implementations
├── Flip.sh             # Flip-specific implementations
├── SmartPro.sh         # SmartPro-specific implementations
├── SmartProS.sh        # SmartProS-specific implementations
├── Pixel2.sh           # Pixel2-specific implementations
├── Brick.sh            # Brick-specific implementations
├── common32bit.sh      # Shared 32-bit abstractions
├── common64bit.sh      # Shared 64-bit abstractions
└── utils/
    ├── cpu_control_functions.sh    # CPU frequency/governor control
    ├── watchdog_launcher.sh        # Launch background watchdogs
    ├── legacy_display.sh           # Display abstraction
    ├── rumble.sh                   # GPIO vibration control
    ├── sleep_functions.sh          # Sleep/suspend state handlers
    ├── flip_a30_brightness.sh      # Device-specific brightness
    ├── miyoomini/mm_set_volume.py  # MiyooMini volume control
    └── smartpros/adaptive_fan.py   # TrimUI fan management
```

### Device File Structure

Each device file defines platform-specific functions. Example from `A30.sh`:

```bash
#!/bin/bash
# platform/device_functions/A30.sh
# Miyoo A30 specific implementations

# Required functions
get_python_path() {
    echo "/usr/bin/python3"
}

get_config_path() {
    echo "/mnt/SDCARD"
}

cores_online() {
    cat /proc/cpuinfo | grep -c "processor"
}

set_performance() {
    # A30-specific performance mode
    echo "performance" > "${CPUGOV_PATH}"
    echo 1200000 > "${CPUFREQ_PATH}scaling_max_freq"
}

set_powersave() {
    echo "powersave" > "${CPUGOV_PATH}"
    echo 600000 > "${CPUFREQ_PATH}scaling_max_freq"
}

set_overclock() {
    # A30 supports 1344MHz overclocking
    echo 1344000 > "${CPUFREQ_PATH}scaling_max_freq"
    echo "performance" > "${CPUGOV_PATH}"
}

vibrate() {
    force=${1:-50}
    duration=${2:-100}

    # A30 vibration via GPIO48
    if [ -d "${VIBRATION_PATH}" ]; then
        echo 1 > "${VIBRATION_PATH}/value"
        sleep 0.${duration}
        echo 0 > "${VIBRATION_PATH}/value"
    fi
}

get_brightness() {
    read -r value < "${DEVICE_BRIGHTNESS_PATH}"
    # Convert raw value (0-255) to level (0-10)
    echo $((value * 10 / 255))
}

set_brightness() {
    level=$1
    # Convert level (0-10) to raw value (0-255)
    raw_value=$((level * 255 / 10))
    echo "$raw_value" > "${DEVICE_BRIGHTNESS_PATH}"
}

rgb_led() {
    # A30 doesn't support RGB LEDs
    log_message "RGB LED not supported on A30"
}

enable_or_disable_rgb() {
    # A30 doesn't support RGB LEDs
    log_message "RGB LED not supported on A30"
}

device_init() {
    # Initialize A30 hardware
    set_smart           # Default to balanced mode
    get_brightness      # Initialize brightness
}
```

### Shared Architecture Functions

#### common32bit.sh (32-bit Devices)

Used by A30 and MiyooMini for shared 32-bit abstractions:

```bash
# Shared CPU control for 32-bit systems
set_smart() {
    echo "ondemand" > "${CPUGOV_PATH}"
}

# Shared 32-bit memory management
setup_32bit_ld_path() {
    export LD_LIBRARY_PATH="/lib:/usr/lib:/mnt/SDCARD/App/MiyooMini/lib"
}
```

#### common64bit.sh (64-bit Devices)

Used by Flip, SmartPro, SmartProS, Pixel2, Brick for shared 64-bit abstractions:

```bash
# Shared CPU control for 64-bit systems
set_smart() {
    echo "schedutil" > "${CPUGOV_PATH}"
}

# Shared 64-bit memory management
setup_64bit_ld_path() {
    export LD_LIBRARY_PATH="/lib64:/usr/lib64:/mnt/SDCARD/App/Platform/lib64"
}

# 64-bit brightness control
set_brightness() {
    level=$1
    # 64-bit systems use different brightness scale
    raw_value=$((level * 100))
    echo "$raw_value" > "${DEVICE_BRIGHTNESS_PATH}"
}
```

### Platform-Specific Utils

#### cpu_control_functions.sh

```bash
# Generic CPU control functions used by all platforms

set_cpu_frequency() {
    cpu=$1
    frequency=$2

    if [ -f "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq" ]; then
        echo "$frequency" > "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_max_freq"
    fi
}

set_cpu_governor() {
    governor=$1
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/; do
        echo "$governor" > "${cpu}/scaling_governor"
    done
}

get_cpu_frequency() {
    cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq
}
```

#### rumble.sh

GPIO-based vibration control (works on all Miyoo and TrimUI devices):

```bash
vibrate() {
    gpio_pin=$1
    duration=${2:-100}
    intensity=${3:-50}

    if [ ! -d "/sys/class/gpio/gpio${gpio_pin}" ]; then
        echo "$gpio_pin" > /sys/class/gpio/export
    fi

    # Simulate intensity with pulse-width modulation
    on_time=$((duration * intensity / 100))
    off_time=$((duration - on_time))

    echo 1 > "/sys/class/gpio/gpio${gpio_pin}/value"
    sleep 0.$(printf "%03d" "$on_time")
    echo 0 > "/sys/class/gpio/gpio${gpio_pin}/value"
}
```

## Implementation Examples

### Example 1: CPU Governor Setting (Cross-Platform)

**Goal:** Change CPU mode to performance without device-specific knowledge

```bash
#!/bin/bash

source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# This works the same on all devices!
set_performance

# On A30: Sets frequency to 1.2GHz, governor to "performance"
# On MiyooMini: Sets frequency to 1.0GHz, governor adapted for ARMv7
# On Flip: Sets frequency to 2.0GHz, governor to "performance"
# On SmartPro: Sets frequency to 2.4GHz, governor with GPU coordination
```

**How it works:**

1. `set_performance()` is defined in device-specific files
2. Automatically routes to correct implementation
3. Each device adjusts frequencies and governors appropriately

### Example 2: Display Brightness Control

```bash
#!/bin/bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# Get current brightness (0-10 scale, works on all devices)
CURRENT=$(get_brightness)

# Increase brightness by 1 level (hardware-agnostic)
NEW_LEVEL=$((CURRENT + 1))
[ "$NEW_LEVEL" -gt 10 ] && NEW_LEVEL=10

set_brightness "$NEW_LEVEL"
```

**Platform Handling:**

- **A30:** Converts level (0-10) → raw value (0-255) for `/sys/class/backlight/*/brightness`
- **MiyooMini:** Converts level (0-10) → raw value (0-255) for `/sys/class/backlight/*/brightness`
- **Flip:** Uses platform-specific scaling via `flip_a30_brightness.sh`
- **SmartPro:** Uses 64-bit brightness scaling with different hardware path

### Example 3: LED Control (TrimUI only)

```bash
#!/bin/bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# This code works on all platforms - TrimUI logs success, Miyoo logs unsupported
rgb_led "blue"              # SmartPro turns blue, MiyooMini logs "not supported"
enable_or_disable_rgb "on"  # SmartPro enables, MiyooMini is no-op
```

**Device Behavior:**

- **TrimUI (SmartPro, SmartProS, Brick):** Genuine RGB LED control via sysfs
- **Miyoo (A30, MiyooMini, Flip, Pixel2):** Function silently logs unsupported, continues execution

## Adding Support for New Devices

### Step 1: Create Platform Configuration File

Create `platform/NewDevice.cfg`:

```bash
#!/bin/bash
# platform/NewDevice.cfg
# NewDevice Hardware Configuration
# CPU: [Processor details]

# Input Event Paths (find with: cat /proc/bus/input/devices)
export EVENT_PATH_BUTTONS="/dev/input/event[X]"
export EVENT_PATH_POWER="/dev/input/event[Y]"
# ... other event paths

# Button Key Codes (find with: evtest)
export B_A=305
export B_B=304
# ... other button codes

# Display Paths
export DEVICE_BRIGHTNESS_PATH="/sys/class/backlight/[device]/brightness"
export BRIGHTNESS_MAX=255

# ... other hardware paths
```

### Step 2: Create Device Function File

Create `platform/device_functions/NewDevice.sh`:

```bash
#!/bin/bash
# platform/device_functions/NewDevice.sh
# NewDevice specific implementations

# Required functions (all must be implemented)
get_python_path() {
    echo "/usr/bin/python3"
}

get_config_path() {
    echo "/mnt/SDCARD"
}

cores_online() {
    cat /proc/cpuinfo | grep -c "processor"
}

set_smart() {
    # Device-specific balanced mode
    echo "schedutil" > "${CPUGOV_PATH}"
}

set_performance() {
    # Device-specific performance mode
    echo "performance" > "${CPUGOV_PATH}"
}

# ... implement other required functions
```

### Step 3: Update Device Detection

Edit `helperFunctions.sh` device detection section:

```bash
elif grep -q "newdevice_cpu_signature" /proc/cpuinfo; then
    PLATFORM="NewDevice"
    BRAND="Manufacturer"
fi
```

### Step 4: Update Architecture Detection (if needed)

If NewDevice uses new architecture, update common32bit.sh or common64bit.sh accordingly.

### Step 5: Test on All Code Paths

1. **System Management:** `runtime.sh` → device initialization
2. **Emulator Launch:** Game launching → CPU mode switching
3. **Watchdog Monitoring:** Button/lid input handling
4. **Network Services:** Service starting/stopping
5. **Power Management:** Shutdown and sleep sequences

## Platform Capability Matrix

| Feature        | A30 | MiyooMini | Flip | SmartPro | SmartProS | Pixel2 | Brick |
| -------------- | --- | --------- | ---- | -------- | --------- | ------ | ----- |
| CPU Governor   | ✓   | ✓         | ✓    | ✓        | ✓         | ✓      | ✓     |
| Overclock      | ✓   | ✗         | ✗    | ✗        | ✗         | ✗      | ✗     |
| Vibration      | ✓   | ✓         | ✓    | ✓        | ✓         | ✓      | ✓     |
| RGB LED        | ✗   | ✗         | ✗    | ✓        | ✓         | ✗      | ✓     |
| Headphone Jack | ✗   | ✗         | ✓    | ✓        | ✓         | ✗      | ✗     |
| Lid Sensor     | ✗   | ✗         | ✓    | ✓        | ✓         | ✗      | ✓     |
| Fan Control    | ✗   | ✗         | ✗    | ✓        | ✓         | ✗      | ✓     |

## Performance Implications

### CPU Frequency Per Platform

| Device    | Idle    | Smart    | Performance | Overclock |
| --------- | ------- | -------- | ----------- | --------- |
| A30       | 600 MHz | 1000 MHz | 1200 MHz    | 1344 MHz  |
| MiyooMini | 600 MHz | 1000 MHz | 1200 MHz    | -         |
| Flip      | 800 MHz | 1500 MHz | 2000 MHz    | -         |
| SmartPro  | 800 MHz | 1800 MHz | 2400 MHz    | -         |
| SmartProS | 800 MHz | 1800 MHz | 2400 MHz    | -         |
| Pixel2    | 800 MHz | 1500 MHz | 2000 MHz    | -         |
| Brick     | 800 MHz | 1600 MHz | 2200 MHz    | -         |

These frequencies are tuned per device for optimal balance between performance and power consumption.

## Debugging Platform Issues

### To determine which platform is detected:

```bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
echo "Platform: $PLATFORM"
echo "Architecture: $PLATFORM_ARCHITECTURE"
echo "Brand: $BRAND"
```

### To test device functions:

```bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# Test a function
get_brightness
set_brightness 5
vibrate 100 200
```

### To check hardware paths:

```bash
# Input devices
cat /proc/bus/input/devices

# Display paths
ls -la /sys/class/backlight/

# CPU frequency paths
ls -la /sys/devices/system/cpu/cpu0/cpufreq/

# Battery
ls -la /sys/class/power_supply/battery/

# LEDs (TrimUI)
ls -la /sys/class/leds/
```
