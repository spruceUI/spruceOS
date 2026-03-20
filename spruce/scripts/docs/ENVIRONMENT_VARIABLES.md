# Environment Variables Reference

This document describes all environment variables used across SpruceOS scripts. These variables are set during system initialization and used throughout the script ecosystem for device abstraction, configuration, and runtime state management.

## Table of Contents

1. [System Configuration Variables](#system-configuration-variables)
2. [Hardware Path Variables](#hardware-path-variables)
3. [Button Mapping Variables](#button-mapping-variables)
4. [Directory and Path Variables](#directory-and-path-variables)
5. [Configuration Variables](#configuration-variables)
6. [State and Flags](#state-and-flags)
7. [Cross-Script Usage Patterns](#cross-script-usage-patterns)

## System Configuration Variables

### Core Platform Detection

| Variable                 | Set By                         | Values                                                   | Usage                              |
| ------------------------ | ------------------------------ | -------------------------------------------------------- | ---------------------------------- |
| `$PLATFORM`              | `helperFunctions.sh`           | A30, MiyooMini, Flip, SmartPro, SmartProS, Pixel2, Brick | Device model identification        |
| `$PLATFORM_ARCHITECTURE` | `helperFunctions.sh` (derived) | armhf, aarch64                                           | 32-bit vs 64-bit architecture      |
| `$BRAND`                 | `platform/device.sh`           | Miyoo, TrimUI                                            | Device manufacturer                |
| `$DISPLAY_ASPECT_RATIO`  | Device functions               | 16:9, 4:3                                                | Screen aspect ratio for UI scaling |

### System JSON Configuration

| Variable               | Set By               | Path                                        | Usage                                     |
| ---------------------- | -------------------- | ------------------------------------------- | ----------------------------------------- |
| `$SYSTEM_JSON`         | `helperFunctions.sh` | `/mnt/SDCARD/spruce/<PLATFORM>-system.json` | Main settings file (all configs via `jq`) |
| `$SYSTEM_SETTINGS_DIR` | (derived)            | `/mnt/SDCARD/spruce/`                       | Settings directory root                   |
| `$CONFIG_DIR`          | (derived)            | `/mnt/SDCARD/spruce/config/`                | Persistent configuration storage          |

### Example: Reading Settings

```bash
# From helperFunctions.sh
get_config_value '.menuOptions.System.swapfileSize.selected'
# Returns: "256MB"

# Direct jq access
jq '.theme' "$SYSTEM_JSON"
# Returns: "SPRUCE"

# WiFi state
jq '.wifi' "$SYSTEM_JSON"
# Returns: 0 or 1
```

## Hardware Path Variables

### Input Device Paths

Button and input device paths are platform-specific and defined in platform configuration files (`platform/*.cfg`):

| Variable                 | Example Value       | Purpose                    |
| ------------------------ | ------------------- | -------------------------- |
| `$EVENT_PATH_POWER`      | `/dev/input/event0` | Power button input event   |
| `$EVENT_PATH_BUTTONS`    | `/dev/input/event1` | Main button inputs         |
| `$EVENT_PATH_JOYSTICK`   | `/dev/input/event2` | Analog stick/D-pad inputs  |
| `$EVENT_PATH_TOUCHPAD`   | `/dev/input/event3` | Touchpad (if device has)   |
| `$EVENT_PATH_LID`        | `/dev/input/event4` | Lid sensor (if device has) |
| `$EVENT_PATH_BRIGHTNESS` | `/dev/input/event5` | Brightness button inputs   |

### Display and Backlight

| Variable                  | Example Value                       | Purpose                  |
| ------------------------- | ----------------------------------- | ------------------------ |
| `$DEVICE_BRIGHTNESS_PATH` | `/sys/class/backlight/*/brightness` | Backlight device control |
| `$BRIGHTNESS_MAX`         | 255                                 | Maximum brightness value |
| `$BRIGHTNESS_MIN`         | 0                                   | Minimum brightness value |
| `$DISPLAY_DEVICE`         | `/dev/fb0`                          | Framebuffer device       |

### LED Control (TrimUI only)

| Variable      | Example Value                           | Purpose               |
| ------------- | --------------------------------------- | --------------------- |
| `$LED_PATH`   | `/sys/class/leds/`                      | LED device base path  |
| `$LED_LEFT`   | `/sys/class/leds/led_left/brightness`   | Left LED (RGB zone)   |
| `$LED_RIGHT`  | `/sys/class/leds/led_right/brightness`  | Right LED (RGB zone)  |
| `$LED_MIDDLE` | `/sys/class/leds/led_middle/brightness` | Middle LED (RGB zone) |
| `$LED_1`      | `/sys/class/leds/led1/brightness`       | Zone 1 LED            |
| `$LED_2`      | `/sys/class/leds/led2/brightness`       | Zone 2 LED            |

### Audio Devices

| Variable                | Example Value                         | Purpose               |
| ----------------------- | ------------------------------------- | --------------------- |
| `$DEVICE_AUDIO_OUTPUT`  | `/dev/snd/pcmC*D0p`                   | Main audio output PCM |
| `$DEVICE_AUDIO_CONTROL` | `/dev/snd/controlC*`                  | Audio mixer control   |
| `$ASOUND_RC_PATH`       | `/etc/asound.rc` or `$HOME/.asoundrc` | ALSA configuration    |

### CPU and Thermal

| Variable        | Example Value                                           | Purpose               |
| --------------- | ------------------------------------------------------- | --------------------- |
| `$CPUFREQ_PATH` | `/sys/devices/system/cpu/cpu*/cpufreq/`                 | CPU frequency scaling |
| `$CPUGOV_PATH`  | `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` | CPU governor control  |
| `$THERMAL_ZONE` | `/sys/class/thermal/thermal_zone0/temp`                 | Temperature sensor    |

### Battery and Power

| Variable            | Example Value                                 | Purpose                    |
| ------------------- | --------------------------------------------- | -------------------------- |
| `$BATTERY_PATH`     | `/sys/class/power_supply/battery/`            | Battery status directory   |
| `$BATTERY_CAPACITY` | `/sys/class/power_supply/battery/capacity`    | Current battery percentage |
| `$BATTERY_VOLTAGE`  | `/sys/class/power_supply/battery/voltage_now` | Battery voltage            |
| `$POWER_STATUS`     | `/sys/class/power_supply/battery/status`      | Charging/Discharging state |

## Button Mapping Variables

All button mappings are defined in `platform/*.cfg` files. They contain key codes from Linux input subsystem:

### Standard Button Keys

```bash
$B_A                    # A/Cross button
$B_B                    # B/Circle button
$B_X                    # X/Square button
$B_Y                    # Y/Triangle button

$B_L1                   # Left shoulder 1 (L1)
$B_L2                   # Left shoulder 2 (L2)
$B_R1                   # Right shoulder 1 (R1)
$B_R2                   # Right shoulder 2 (R2)

$B_UP                   # D-Pad up
$B_DOWN                 # D-Pad down
$B_LEFT                 # D-Pad left
$B_RIGHT                # D-Pad right

$B_START                # Start button
$B_SELECT               # Select button
$B_MENU                 # Menu/Home button
$B_POWER                # Power button
```

### Extended Button Keys

```bash
$B_L3                   # Left analog stick press
$B_R3                   # Right analog stick press
$B_VOLUP                # Volume up
$B_VOLDOWN              # Volume down
$B_LID                  # Lid open/close event
```

### Example Usage in watchdogs

```bash
# From buttons_watchdog.sh
getevent "$EVENT_PATH_BRIGHTNESS" | grep "EV_KEY" | \
  while IFS= read -r line; do
    if echo "$line" | grep -q "$B_VOLUP"; then
      increase_brightness
    elif echo "$line" | grep -q "$B_VOLDOWN"; then
      decrease_brightness
    fi
  done
```

## Directory and Path Variables

### System Directories

| Variable          | Path                          | Purpose                 |
| ----------------- | ----------------------------- | ----------------------- |
| `$SPRUCE_HOME`    | `/mnt/SDCARD/spruce/`         | SpruceOS root directory |
| `$SPRUCE_SCRIPTS` | `/mnt/SDCARD/spruce/scripts/` | Scripts directory       |
| `$SPRUCE_FLAGS`   | `/mnt/SDCARD/spruce/flags/`   | Runtime flag markers    |
| `$SPRUCE_CACHE`   | `/mnt/SDCARD/spruce/cache/`   | Temporary cache files   |
| `$THEMES_DIR`     | `/mnt/SDCARD/Themes/`         | UI theme files          |
| `$ICONS_DIR`      | `/mnt/SDCARD/Icons/`          | Icon collections        |

### Emulator Directories

| Variable     | Path                 | Purpose                       |
| ------------ | -------------------- | ----------------------------- |
| `$EMUS_DIR`  | `/mnt/SDCARD/Emu/`   | Emulator installations        |
| `$ROMS_DIR`  | `/mnt/SDCARD/Roms/`  | ROM files organized by system |
| `$SAVES_DIR` | `/mnt/SDCARD/Saves/` | Game saves and screenshots    |
| `$BIOS_DIR`  | `/mnt/SDCARD/BIOS/`  | System BIOS files             |

### RetroArch Directories

| Variable              | Path                              | Purpose                   |
| --------------------- | --------------------------------- | ------------------------- |
| `$RA_CONFIG_DIR`      | `/mnt/SDCARD/RetroArch/`          | RetroArch main config     |
| `$RA_PLATFORM_CONFIG` | `/mnt/SDCARD/RetroArch/platform/` | Platform-specific configs |
| `$RA_CORES_DIR`       | `/mnt/SDCARD/RetroArch/cores/`    | Libretro cores            |
| `$RA_OVERLAYS`        | `/mnt/SDCARD/RetroArch/overlays/` | Screen overlays           |

### Application Directories

| Variable          | Path                          | Purpose              |
| ----------------- | ----------------------------- | -------------------- |
| `$APP_DIR`        | `/mnt/SDCARD/App/`            | Utility applications |
| `$PORTMASTER_DIR` | `/mnt/SDCARD/App/PortMaster/` | GamePorts collection |
| `$SCUMMVM_DIR`    | `/mnt/SDCARD/App/ScummVM/`    | ScummVM games        |

### Log Directories

| Variable      | Path                                  | Purpose              |
| ------------- | ------------------------------------- | -------------------- |
| `$LOG_DIR`    | `/mnt/SDCARD/Saves/spruce/`           | Main log directory   |
| `$SYSTEM_LOG` | `/var/log/messages`                   | System kernel log    |
| `$SPRUCE_LOG` | `/mnt/SDCARD/Saves/spruce/spruce.log` | Main application log |

## Configuration Variables

### Emulator Configuration Paths

| Variable              | Path                        | Purpose                    |
| --------------------- | --------------------------- | -------------------------- |
| `$EMU_CONFIG_FILE`    | `/Emu/<SYSTEM>/config.json` | Per-system user config     |
| `$EMU_SETUP_DIR`      | `/Emu/.emu_setup/<SYSTEM>/` | Factory defaults           |
| `$EMU_RUNTIME_CONFIG` | `/tmp/<SYSTEM>_runtime.cfg` | Runtime-specific overrides |

### Specific Emulator Configs

| Variable           | Example                                                   | Purpose                     |
| ------------------ | --------------------------------------------------------- | --------------------------- |
| `$RA_CONFIG_FILE`  | `/mnt/SDCARD/RetroArch/retroarch.cfg`                     | Main RetroArch config       |
| `$RA_PLATFORM_CFG` | `/mnt/SDCARD/RetroArch/platform/retroarch-<PLATFORM>.cfg` | Platform-specific RA config |
| `$NDS_CONFIG_DIR`  | `/Saves/NDS/`                                             | DraStic configuration       |
| `$PSP_CONFIG_DIR`  | `/Saves/PSP/`                                             | PPSSPP configuration        |
| `$SCUMMVM_CONFIG`  | `/Saves/SCUMMVM/scummvm.ini`                              | ScummVM configuration       |

### Network Configuration Files

| Variable            | Path                            | Purpose              |
| ------------------- | ------------------------------- | -------------------- |
| `$SSH_KEY_DIR`      | `/etc/dropbear/`                | SSH host keys        |
| `$SAMBA_CONFIG`     | `/etc/samba/smb.conf`           | Samba configuration  |
| `$SYNCTHING_CONFIG` | `/home/root/.config/syncthing/` | Syncthing setup      |
| `$SFTPGO_CONFIG`    | `/etc/sftpgo/`                  | SFTPGo configuration |

## State and Flags

### Runtime State Variables

| Variable           | Scope         | Set By             | Usage                              |
| ------------------ | ------------- | ------------------ | ---------------------------------- |
| `$HOME`            | Process-local | OS/Script          | Working directory                  |
| `$PATH`            | Process-local | OS/Platform files  | Executable search path             |
| `$LD_LIBRARY_PATH` | Process-local | Emulator launchers | Shared library paths               |
| `$LD_PRELOAD`      | Process-local | Audio setup        | Library preloading for audio fixes |

### Flag Files (in `/mnt/SDCARD/spruce/flags/`)

Flag files serve as temporary markers for inter-process communication:

| Flag                   | Set By                         | Checked By         | Meaning                          |
| ---------------------- | ------------------------------ | ------------------ | -------------------------------- |
| `silentUnpacker`       | archiveUnpacker.sh             | principal.sh       | Archive unpacking in progress    |
| `first_boot_$PLATFORM` | firstboot.sh                   | runtime.sh         | First boot detected for platform |
| `in_menu`              | principal.sh                   | watchdogs          | Currently in menu mode           |
| `lastgame.lock`        | principal.sh                   | runtimeHelper.sh   | Last game for autoresume         |
| `low_battery`          | low_power_warning.sh           | watchdogs          | Battery critically low           |
| `perfectOverlays`      | applySetting/applyPerfectOs.sh | emulator launchers | Perfect overlays enabled         |
| `log_verbose`          | (user config)                  | Logging functions  | Verbose logging mode             |
| `pb.longpress`         | power_button_watchdog_v2.sh    | principal.sh       | Power button long press detected |
| `sleep_helper_started` | sleep_helper.sh                | idlemon scripts    | Sleep mode active                |
| `ota_completed`        | runtimeHelper.sh               | firstboot.sh       | OTA update completed             |

### Temporary State (in `/tmp/`)

| File                        | Set By                      | Checked By      | Purpose                   |
| --------------------------- | --------------------------- | --------------- | ------------------------- |
| `/tmp/cmd_to_run.sh`        | PyUI/MainUI                 | principal.sh    | Command to execute next   |
| `/tmp/powerbtn`             | power_button_watchdog_v2.sh | sleep_helper.sh | Power button state        |
| `/tmp/sleep_helper_started` | sleep_helper.sh             | watchdogs       | Sleep mode marker         |
| `/tmp/host_msg`             | networkservices.sh          | (network apps)  | Network message broadcast |
| `/tmp/miyoo_inputd/`        | (input daemon)              | watchdogs       | Input event sockets       |

## Cross-Script Usage Patterns

### Configuration Reading Pattern

Most scripts follow this pattern for reading settings:

```bash
#!/bin/bash

# Source helper functions (loads $SYSTEM_JSON)
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Read setting using helper function
SETTING_VALUE=$(get_config_value '.menuOptions.System.swapfileSize.selected')

# Or direct jq access
WIFI_STATE=$(jq '.wifi' "$SYSTEM_JSON")

# Read platform-specific value
CPU_MODE=$(jq ".menuOptions.Governor_${PLATFORM}.selected" "$SYSTEM_JSON")
```

### Device Detection Pattern

```bash
#!/bin/bash

source /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# $PLATFORM is now set to detected device
case "$PLATFORM" in
  A30|MiyooMini)
    # 32-bit device handling
    source platform/device_functions/common32bit.sh
    ;;
  Flip|SmartPro|SmartProS|Pixel2)
    # 64-bit device handling
    source platform/device_functions/common64bit.sh
    ;;
esac

# Load platform-specific functions
source platform/device_functions/${PLATFORM}.sh
```

### Setting Values with jq

```bash
#!/bin/bash

# Update a setting
NEW_SWAP_SIZE="512MB"
jq ".menuOptions.System.swapfileSize.selected = \"$NEW_SWAP_SIZE\"" "$SYSTEM_JSON" > /tmp/system.json.tmp
mv /tmp/system.json.tmp "$SYSTEM_JSON"

# Multi-value update
jq '.menuOptions.Governor.selected = "performance" | .menuOptions.System.swapfileSize.selected = "512MB"' \
  "$SYSTEM_JSON" > /tmp/system.json.tmp
mv /tmp/system.json.tmp "$SYSTEM_JSON"
```

### Flag Management Pattern

```bash
#!/bin/bash

source /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Add a flag (persistent in /mnt/SDCARD/spruce/flags/)
flag_add "myProcessRunning"

# Check if flag exists
if flag_check "myProcessRunning"; then
  echo "Process is running"
fi

# Check with temporary flag (in /tmp)
flag_add "tmpMarker" --tmp

# Remove flag
flag_remove "myProcessRunning"
```

## Platform-Specific Variable Sets

### Miyoo A30 (32-bit)

```bash
$PLATFORM="A30"
$PLATFORM_ARCHITECTURE="armhf"
$BRAND="Miyoo"
# Plus A30-specific button mappings and paths from platform/A30.cfg
```

### Miyoo Mini (32-bit)

```bash
$PLATFORM="MiyooMini"
$PLATFORM_ARCHITECTURE="armhf"
$BRAND="Miyoo"
# Plus MiyooMini-specific button mappings and paths from platform/MiyooMini.cfg
```

### Miyoo Flip (64-bit)

```bash
$PLATFORM="Flip"
$PLATFORM_ARCHITECTURE="aarch64"
$BRAND="Miyoo"
# Plus Flip-specific button mappings and paths from platform/Flip.cfg
```

### TrimUI SmartPro (64-bit)

```bash
$PLATFORM="SmartPro"
$PLATFORM_ARCHITECTURE="aarch64"
$BRAND="TrimUI"
# Plus SmartPro-specific RGB LED paths and button mappings from platform/SmartPro.cfg
```

### TrimUI Brick (64-bit)

```bash
$PLATFORM="Brick"
$PLATFORM_ARCHITECTURE="aarch64"
$BRAND="TrimUI"
# Plus Brick-specific button mappings from platform/Brick.cfg
```

### TrimUI SmartProS (64-bit)

```bash
$PLATFORM="SmartProS"
$PLATFORM_ARCHITECTURE="aarch64"
$BRAND="TrimUI"
# Plus SmartProS-specific button mappings from platform/SmartProS.cfg
```

## Accessing Variables in Scripts

### Best Practice: Always Source helperFunctions.sh First

```bash
#!/bin/bash
# This ensures all base variables are loaded

source /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Now $PLATFORM, $SYSTEM_JSON, and other core variables are available
echo "Running on $PLATFORM with system config: $SYSTEM_JSON"

# Load platform-specific functions
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh

# Use platform-specific variables and functions
set_performance_mode
```

### For Scripts That Need Minimal Output

```bash
#!/bin/bash
# Minimal initialization for background watchdogs

source /mnt/SDCARD/spruce/scripts/helperFunctions.sh 2>/dev/null

# Use variables but suppress helper function logs
PLATFORM_ARCH="$PLATFORM_ARCHITECTURE"
```

## Common Variable Combinations

### For Emulator Configuration

```bash
# System-specific config file
$SAVES_DIR/$SYSTEM_NAME/config.json

# Platform override config
$SAVES_DIR/$SYSTEM_NAME/${PLATFORM}_config.json

# Global emulator config
$RA_PLATFORM_CONFIG/retroarch-${PLATFORM}.cfg
```

### For Device Control

```bash
# Device hardware paths
read -r CURRENT_BRIGHTNESS < "$DEVICE_BRIGHTNESS_PATH"

# Button input
getevent "$EVENT_PATH_BUTTONS" | grep "$B_A"

# LED control
echo 255 > "$LED_LEFT"
```

### For Configuration Access

```bash
# Read single value
SETTING=$(get_config_value '.menuOptions.path.to.setting.selected')

# Read with jq
VALUE=$(jq '.menuOptions.System.swapfileSize.selected' "$SYSTEM_JSON")

# Update setting
jq ".menuOptions.System.key = \"value\"" "$SYSTEM_JSON" > /tmp/system.json.tmp && \
  mv /tmp/system.json.tmp "$SYSTEM_JSON"
```

## Logging and Verbosity

### Log Verbosity Control

```bash
# Check if verbose logging is enabled
if flag_check "log_verbose"; then
  echo "[VERBOSE] Debug information" | tee -a "$SPRUCE_LOG"
else
  # Normal logging without debug
  echo "[INFO] Message" >> "$SPRUCE_LOG"
fi
```

### Audit and History

```bash
# Battery history
echo "$(date): Battery at $(cat $BATTERY_CAPACITY)%" >> /mnt/SDCARD/Saves/spruce/battery_log.txt

# Activity logging
echo "$(date): Game launched: $GAME_NAME" >> "$SPRUCE_LOG"
```

## Notes and Best Practices

1. **Always source `helperFunctions.sh` before using `$PLATFORM` or `$SYSTEM_JSON`**
2. **Use `get_config_value()` function** rather than direct `jq` when available
3. **Device paths are platform-specific** - always reference variables instead of hardcoding paths
4. **Flag files should be used** for inter-script communication instead of temporary files
5. **Log files use append mode** (`>>`) to preserve history; use `tee -a` for console + file output
6. **JSON updates should write to temporary file first**, then `mv` to ensure atomicity
7. **Button mappings vary by device** - never hardcode key codes, always use `$B_*` variables
8. **CPU frequency paths** are architecture-specific; use platform abstraction functions instead
