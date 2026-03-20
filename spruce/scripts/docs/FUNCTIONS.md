# Functions Reference

This document provides a comprehensive reference of all functions defined across SpruceOS scripts, organized by category and subsystem.

## Table of Contents

1. [Helper Functions](#helper-functions)
2. [Device Control Functions](#device-control-functions)
3. [Emulator Control Functions](#emulator-control-functions)
4. [Network Service Functions](#network-service-functions)
5. [Watchdog Functions](#watchdog-functions)
6. [System Management Functions](#system-management-functions)
7. [Configuration Functions](#configuration-functions)

## Helper Functions

Helper functions are core utilities defined in `helperFunctions.sh`, sourced by most scripts.

### Device Detection and Initialization

#### `detect_device()`

**Purpose:** Detect the current device platform by reading `/proc/cpuinfo`

**Usage:**

```bash
detect_device
```

**Sets:**

- `$PLATFORM` - Device model (A30, MiyooMini, Flip, SmartPro, SmartProS, Pixel2, Brick)
- `$PLATFORM_ARCHITECTURE` - Architecture (armhf or aarch64)

**Example:**

```bash
source helperFunctions.sh
# Platform variables are automatically set during sourcing
echo "Running on: $PLATFORM ($PLATFORM_ARCHITECTURE)"
```

### Configuration Functions

#### `get_config_value(path)`

**Purpose:** Retrieve a configuration value from the system JSON file using jq path

**Parameters:**

- `path` - jq path to the configuration key (e.g., `.menuOptions.System.swapfileSize.selected`)

**Returns:** Configuration value or empty string if not found

**Usage:**

```bash
SWAP_SIZE=$(get_config_value '.menuOptions.System.swapfileSize.selected')
echo "Swap size: $SWAP_SIZE"  # Output: "256MB"
```

**Common Paths:**

```bash
# System settings
get_config_value '.menuOptions.System.swapfileSize.selected'
get_config_value '.menuOptions.System.useZRAM.selected'
get_config_value '.menuOptions.System.overclockSpeedA30.selected'
get_config_value '.menuOptions.System.rumbleIntensity.selected'
get_config_value '.menuOptions.System.enableLidSensor.selected'

# Network settings
get_config_value '.menuOptions.Network.enableSamba.selected'
get_config_value '.menuOptions.Network.enableSSH.selected'
get_config_value '.menuOptions.Network.enableSFTPGo.selected'
get_config_value '.menuOptions.Network.enableSyncthing.selected'

# Emulator settings
get_config_value '.menuOptions.Emulator.raAutoSave.selected'
get_config_value '.menuOptions.Emulator.raAutoLoad.selected'
get_config_value '.menuOptions.Emulator.perfectOverlays.selected'

# Device-specific
get_config_value ".menuOptions.Governor_${PLATFORM}.selected"
get_config_value ".menuOptions.Governor.selected"

# Theme and general
get_config_value '.theme'
get_config_value '.wifi'
```

#### `set_config_value(path, value)`

**Purpose:** Update a configuration value in the system JSON file

**Parameters:**

- `path` - jq path to the configuration key
- `value` - New value to set

**usage:**

```bash
set_config_value '.menuOptions.System.swapfileSize.selected' '512MB'
set_config_value '.menuOptions.Network.enableSSH.selected' 'True'
```

**Important:** Uses atomic write with temporary file to prevent corruption:

```bash
jq ".$key = $value" "$SYSTEM_JSON" > /tmp/system.json.tmp && \
  mv /tmp/system.json.tmp "$SYSTEM_JSON"
```

### Flag Management Functions

#### `flag_add(name [--tmp])`

**Purpose:** Create a flag file marker for inter-process communication

**Parameters:**

- `name` - Flag file name (no extension)
- `--tmp` - Optional: create in `/tmp` instead of `/mnt/SDCARD/spruce/flags/`

**Usage:**

```bash
# Persistent flag (survives reboot)
flag_add "myprocess_running"

# Temporary flag (cleared on reboot)
flag_add "process_temp" --tmp
```

**Stored In:**

- Without `--tmp`: `/mnt/SDCARD/spruce/flags/<name>`
- With `--tmp`: `/tmp/<name>`

#### `flag_check(name [--tmp])`

**Purpose:** Check if a flag file exists

**Parameters:**

- `name` - Flag file name to check
- `--tmp` - Optional: check in `/tmp` instead of persistent directory

**Returns:** 0 (success) if flag exists, 1 if not

**Usage:**

```bash
if flag_check "process_running"; then
  echo "Process is currently running"
else
  echo "Process is not running"
fi
```

#### `flag_remove(name [--tmp])`

**Purpose:** Delete a flag file

**Parameters:**

- `name` - Flag file name to remove
- `--tmp` - Optional: remove from `/tmp` instead of persistent directory

**Usage:**

```bash
# When process completes
flag_remove "process_running"
flag_remove "temp_marker" --tmp
```

### Logging Functions

#### `log_message(message)`

**Purpose:** Log a timestamped message to the main log file

**Parameters:**

- `message` - Text to log

**Usage:**

```bash
log_message "Game launched: Pac-Man"
log_message "Syncthing sync completed"
```

**Output:** `[TIMESTAMP] message` appended to `/mnt/SDCARD/Saves/spruce/spruce.log`

#### `log_error(message)`

**Purpose:** Log an error message with ERROR prefix

**Parameters:**

- `message` - Error description

**Usage:**

```bash
log_error "Failed to mount SD card"
log_error "RetroArch exited with code: $?"
```

### Directory Functions

#### `ensure_directory(path)`

**Purpose:** Create a directory tree if it doesn't exist

**Parameters:**

- `path` - Full directory path

**Usage:**

```bash
ensure_directory "/mnt/SDCARD/Saves/GB/config"
ensure_directory "$SAVES_DIR/NDS/Backup"
```

### CPU/Governor Functions (Generic)

#### `set_cpu_governor(governor_name)`

**Purpose:** Change CPU governor (generic implementation, platform-specific in device files)

**Parameters:**

- `governor_name` - Governor mode: "powersave", "performance", "smart", "overclock"

**Usage:**

```bash
set_cpu_governor "performance"      # Gaming mode
set_cpu_governor "powersave"        # Power saving mode
set_cpu_governor "smart"            # Smart CPU management
set_cpu_governor "overclock"        # Maximum performance (A30 only)
```

## Device Control Functions

Device control functions provide a unified interface across all platforms. These are implemented in `platform/device_functions/*.sh` files.

### Required Device Functions (All Platforms)

Each platform file (`A30.sh`, `MiyooMini.sh`, `Flip.sh`, `SmartPro.sh`, etc.) implements these core functions:

#### `get_python_path()`

**Purpose:** Return the path to the Python executable for this platform

**Returns:** Absolute path to Python binary

**Usage:**

```bash
source platform/device_functions/${PLATFORM}.sh
PYTHON=$(get_python_path)
$PYTHON /path/to/script.py
```

**Platform Examples:**

```bash
# Miyoo A30
get_python_path  # Returns: /usr/bin/python3

# TrimUI SmartPro
get_python_path  # Returns: /usr/bin/python3.9
```

#### `get_config_path()`

**Purpose:** Return the base path for platform-specific configuration

**Returns:** Configuration base directory path

**Usage:**

```bash
CONFIG_PATH=$(get_config_path)
cp "$CONFIG_PATH/retroarch.cfg" /tmp/retroarch_backup.cfg
```

#### `cores_online()`

**Purpose:** Get number of CPU cores available online

**Returns:** Integer count of active cores

**Usage:**

```bash
CORES=$(cores_online)
echo "CPU cores available: $CORES"
```

#### `set_smart()`

**Purpose:** Set CPU governor to smart/balanced mode

**Usage:**

```bash
set_smart    # Balanced performance and power consumption
```

#### `set_performance()`

**Purpose:** Set CPU governor to performance mode (maximum CPU frequency)

**Usage:**

```bash
set_performance    # Before launching game
```

#### `set_overclock()`

**Purpose:** Set CPU to overclocked frequency (if supported)

**Note:** Available only on A30. Other platforms will log "not supported"

**Usage:**

```bash
if [ "$PLATFORM" = "A30" ]; then
  set_overclock    # 1344 MHz on A30
fi
```

#### `set_powersave()`

**Purpose:** Set CPU governor to power saving mode (reduced frequency)

**Usage:**

```bash
set_powersave    # Extended battery life
```

#### `vibrate([force] [duration])`

**Purpose:** Trigger device vibration/rumble

**Parameters:**

- `force` - Optional: vibration intensity (0-100, default: based on config)
- `duration` - Optional: milliseconds (default: 100ms)

**Usage:**

```bash
vibrate              # Default rumble
vibrate 50           # 50% intensity
vibrate 100 200      # Full intensity for 200ms
```

**Supported Platforms:**

- A30, MiyooMini, Flip, SmartPro, SmartProS (via GPIO)
- Brick (limited support)
- Pixel2 (limited support)

#### `display_kill()`

**Purpose:** Terminate all display-related processes (SDL, framebuffer, X11)

**Usage:**

```bash
display_kill    # Before emulator launch with custom display settings
```

#### `display(text [x] [y] [duration])`

**Purpose:** Display on-screen text or image

**Parameters:**

- `text` - Text message or image file path
- `x` - Optional: X coordinate (default: center)
- `y` - Optional: Y coordinate (default: center)
- `duration` - Optional: display time in seconds (default: 2)

**Usage:**

```bash
display "Loading game..."
display "Game saved" 50 50 3    # 3 seconds at position (50, 50)
display "/path/to/image.png"    # Display image
```

#### `rgb_led(color [zone])`

**Purpose:** Control RGB LED (TrimUI devices only)

**Parameters:**

- `color` - Color name: "red", "green", "blue", "yellow", "cyan", "magenta", "white", "off"
- `zone` - Optional: LED zone (left, right, middle, 1, 2) - default: all zones

**Usage (TrimUI only):**

```bash
rgb_led "red"                # All red
rgb_led "green" "left"       # Left LED green
rgb_led "blue" "middle"      # Middle LED blue
rgb_led "off" "right"        # Turn right LED off
```

**Note:** On Miyoo devices, this function will log "not supported"

#### `enable_or_disable_rgb([state])`

**Purpose:** Toggle RGB LED on/off (TrimUI only)

**Parameters:**

- `state` - Optional: "on" or "off" (default: toggle)

**Usage:**

```bash
enable_or_disable_rgb "on"      # Enable all LEDs
enable_or_disable_rgb "off"     # Disable all LEDs
enable_or_disable_rgb           # Toggle current state
```

#### `device_init()`

**Purpose:** Initialize device hardware (run once at boot)

**Usage:**

```bash
# Called by runtime.sh during system startup
device_init
```

**Performs:**

- GPIO setup
- Brightness initialization
- LED initialization
- Audio paths setup
- Thermal management initialization

### Platform-Specific Advanced Functions

#### `set_brightness(level)` (A30, Flip, SmartPro, SmartProS)

**Purpose:** Set display brightness to specific level

**Parameters:**

- `level` - Brightness level: 0-10 (10 = maximum)

**Usage:**

```bash
set_brightness 5    # 50% brightness
set_brightness 10   # Maximum brightness
set_brightness 1    # Minimum brightness
```

#### `get_brightness()` (All platforms)

**Purpose:** Get current display brightness level

**Returns:** Current brightness level (0-10 or percentage)

**Usage:**

```bash
CURRENT=$(get_brightness)
echo "Current brightness: $CURRENT"
```

#### `get_battery_percentage()` (All platforms)

**Purpose:** Read current battery percentage

**Returns:** Battery percentage (0-100)

**Usage:**

```bash
BATTERY=$(get_battery_percentage)
if [ "$BATTERY" -lt 10 ]; then
  echo "Battery low!"
fi
```

#### `get_temperature()` (Thermal sensors)

**Purpose:** Read CPU temperature

**Returns:** Temperature in Celsius

**Usage:**

```bash
TEMP=$(get_temperature)
if [ "$TEMP" -gt 80 ]; then
  log_error "Overheating: ${TEMP}°C"
fi
```

#### `headphone_connected()` (Flip only)

**Purpose:** Check if headphones are plugged in

**Returns:** 0 if connected, 1 if not

**Usage:**

```bash
if headphone_connected; then
  echo "Using headphones"
fi
```

#### `lid_open()` (Devices with lid sensor)

**Purpose:** Check if device lid is open

**Returns:** 0 if open, 1 if closed

**Usage:**

```bash
if lid_open; then
  echo "Lid is open - device active"
else
  echo "Lid is closed - device may sleep"
fi
```

## Emulator Control Functions

Emulator functions are located in `emu/lib/*.sh` and handle emulator-specific launching and configuration.

### General Emulator Functions (general_functions.sh)

#### `set_emu_core_from_emu_json(system_name)`

**Purpose:** Read emulator core preference from system JSON and set `$CORE` variable

**Parameters:**

- `system_name` - System name (e.g., "GB", "GBA", "N64")

**Usage:**

```bash
set_emu_core_from_emu_json "GBA"  # Sets $CORE based on JSON preference
echo "Using core: $CORE"
```

**Logic:**

1. Check system-specific override: `.menuOptions.Emulator_$SYSTEM.selected`
2. Check platform override: `.menuOptions.Emulator_${SYSTEM}_${PLATFORM}.selected`
3. Fall back to default core for system

#### `get_emu_startup_path(emu_name game_path)`

**Purpose:** Build the complete startup command for an emulator

**Parameters:**

- `emu_name` - Emulator name (e.g., "retroarch", "drastic", "ppsspp")
- `game_path` - Full path to game ROM/file

**Returns:** Executable command string

**Usage:**

```bash
CMD=$(get_emu_startup_path "retroarch" "/mnt/SDCARD/Roms/GB/Game.gb")
eval "$CMD"      # Execute the command
```

### RetroArch Functions (ra_functions.sh)

#### `load_ra_config_for_system(system_name)`

**Purpose:** Load RetroArch configuration for specific system

**Parameters:**

- `system_name` - System name

**Usage:**

```bash
load_ra_config_for_system "GB"
# Sets up RetroArch with Game Boy-specific config
```

#### `save_ra_screenshot(game_name)`

**Purpose:** Save a screenshot from RetroArch

**Parameters:**

- `game_name` - Name of the game that was running

**Usage:**

```bash
save_ra_screenshot "Super Mario Bros 3"
# Screenshot saved to /mnt/SDCARD/Saves/screenshots/
```

#### `get_ra_core_for_system(system_name)`

**Purpose:** Get the default RetroArch core for a system

**Parameters:**

- `system_name` - System name

**Returns:** Core name (e.g., "genesis_plus_gx", "snes9x")

**Usage:**

```bash
CORE=$(get_ra_core_for_system "MD")    # Returns "genesis_plus_gx"
```

### DraStic Function (drastic_functions.sh)

#### `launch_drastic_nds(game_path)`

**Purpose:** Launch Nintendo DS game using DraStic emulator

**Parameters:**

- `game_path` - Full path to NDS ROM file

**Usage:**

```bash
launch_drastic_nds "/mnt/SDCARD/Roms/NDS/Pokemon Diamond.nds"
```

**Features:**

- Platform-specific launcher (32-bit vs 64-bit)
- Configuration loading
- Overlay setup (optional)
- Save state management

### PPSSPP Functions (ppsspp_functions.sh)

#### `launch_ppsspp_psp(game_path)`

**Purpose:** Launch PlayStation Portable game using PPSSPP

**Parameters:**

- `game_path` - Full path to PSP ROM file (.iso or .cso)

**Usage:**

```bash
launch_ppsspp_psp "/mnt/SDCARD/Roms/PSP/Final Fantasy.iso"
```

**Features:**

- Per-platform configuration
- PSP-specific overlay support
- Controller mapping per device

### ScummVM Functions (scummvm_functions.sh)

#### `launch_scummvm_game(game_id)`

**Purpose:** Launch adventure game using ScummVM

**Parameters:**

- `game_id` - ScummVM game identifier

**Usage:**

```bash
launch_scummvm_game "monkey"  # Monkey Island
launch_scummvm_game "simon1"  # Simon the Sorcerer
```

#### `scan_scummvm_library()`

**Purpose:** Discover installed ScummVM games

**Returns:** List of available game IDs

**Usage:**

```bash
GAMES=$(scan_scummvm_library)
for GAME in $GAMES; do
  echo "Found ScummVM game: $GAME"
done
```

### LED Control Functions (led_functions.sh)

#### `led_effect_startup()`

**Purpose:** Show LED startup effect

**Usage:**

```bash
led_effect_startup    # Boot animation
```

#### `led_effect_gaming()`

**Purpose:** Set LED to gaming profile

**Usage:**

```bash
led_effect_gaming     # Subtle LEDs during gameplay
```

#### `led_effect_charging()`

**Purpose:** Set LED to charging indicator

**Usage:**

```bash
led_effect_charging   # Pulsing LED while charging
```

#### `led_effect_low_battery()`

**Purpose:** Set LED to low battery warning

**Usage:**

```bash
led_effect_low_battery   # Rapid flashing LED
```

#### `led_effect_off()`

**Purpose:** Turn off all LED effects

**Usage:**

```bash
led_effect_off   # Disable LEDs
```

### Game Time Tracking Functions (gtt_functions.sh)

#### `log_game_start(game_name system_name)`

**Purpose:** Record when a game is started

**Parameters:**

- `game_name` - Display name of the game
- `system_name` - System/emulator name

**Usage:**

```bash
log_game_start "Super Mario Bros" "NES"
```

#### `log_game_end(game_name)`

**Purpose:** Record when a game is ended and calculate play time

**Parameters:**

- `game_name` - Display name of the game

**Usage:**

```bash
log_game_end "Super Mario Bros"
# Output: "Played for 1 hour 23 minutes"
```

### Network Functions (network_functions.sh)

#### `stop_network_services()`

**Purpose:** Gracefully stop all network services

**Usage:**

```bash
stop_network_services    # Called before emulator launch
```

**Stops:**

- Syncthing daemon
- SSH server
- SMB/Samba
- SFTPGo
- Web server

#### `start_network_services()`

**Purpose:** Restart network services after emulator

**Usage:**

```bash
start_network_services    # Called after emulator exit
```

## Network Service Functions

Network service functions are located in `network/*.sh` files.

### SSH Functions (sshFunctions.sh)

#### `dropbear_generate_keys()`

**Purpose:** Generate SSH host keys for Dropbear

**Usage:**

```bash
source network/sshFunctions.sh
dropbear_generate_keys
```

#### `start_ssh_process()`

**Purpose:** Start SSH server (Dropbear)

**Usage:**

```bash
start_ssh_process
# SSH now available on port 22
```

#### `stop_ssh_process()`

**Purpose:** Stop SSH server

**Usage:**

```bash
stop_ssh_process
```

### Samba Functions (sambaFunctions.sh)

#### `start_samba_process()`

**Purpose:** Start Samba (SMB file sharing)

**Usage:**

```bash
source network/sambaFunctions.sh
start_samba_process
# Samba shares now available
```

#### `stop_samba_process()`

**Purpose:** Stop Samba service

**Usage:**

```bash
stop_samba_process
```

### Syncthing Functions (syncthingFunctions.sh)

#### `generate_syncthing_config()`

**Purpose:** Generate initial Syncthing configuration

**Usage:**

```bash
source network/syncthingFunctions.sh
generate_syncthing_config
```

#### `repair_syncthing_config()`

**Purpose:** Fix corrupted Syncthing configuration

**Usage:**

```bash
repair_syncthing_config
```

#### `start_syncthing_process()`

**Purpose:** Start Syncthing sync daemon

**Usage:**

```bash
start_syncthing_process
# Syncthing daemon running on port 8384
```

#### `run_syncthing()`

**Purpose:** Run Syncthing in foreground (main run mode)

**Usage:**

```bash
run_syncthing
```

### SFTPGo Functions (sftpgoFunctions.sh)

#### `start_sftpgo_process()`

**Purpose:** Start SFTPGo SFTP server

**Usage:**

```bash
source network/sftpgoFunctions.sh
start_sftpgo_process
```

#### `stop_sftpgo_process()`

**Purpose:** Stop SFTPGo service

**Usage:**

```bash
stop_sftpgo_process
```

### Darkhttpd Functions (darkhttpdFunctions.sh)

#### `start_darkhttpd_process()`

**Purpose:** Start Darkhttpd web server

**Usage:**

```bash
source network/darkhttpdFunctions.sh
start_darkhttpd_process
```

#### `stop_darkhttpd_process()`

**Purpose:** Stop Darkhttpd server

**Usage:**

```bash
stop_darkhttpd_process
```

## Watchdog Functions

Watchdog functions run continuously to monitor hardware events.

### Power Button Watchdog (power_button_watchdog_v2.sh)

#### `detect_power_button_event()`

**Purpose:** Monitor and detect power button press/release events

**Detects:**

- Short press: Sleep/wake toggle
- Long press (2s): Poweroff

**Usage:**

```bash
while true; do
  detect_power_button_event
  sleep 0.1
done
```

### Home Button Watchdog (homebutton_watchdog.sh)

#### `detect_home_button()`

**Purpose:** Monitor home button and trigger appropriate action

**Actions:**

- Pause/Resume DraStic (if running NDS)
- Terminate port if running game port
- Take screenshot if in compatible app

**Usage:**

```bash
detect_home_button
```

### Lid Watchdog (lid_watchdog_v2.sh)

#### `detect_lid_state()`

**Purpose:** Monitor lid sensor for open/close events

**Usage:**

```bash
while true; do
  detect_lid_state
  sleep 1
done
```

### Brightness Button Watchdog (buttons_watchdog.sh)

#### `handle_brightness_button()`

**Purpose:** Monitor brightness buttons and adjust display

**Usage:**

```bash
handle_brightness_button
```

## System Management Functions

### Power Management Functions (save_poweroff.sh)

#### `graceful_shutdown()`

**Purpose:** Perform graceful system shutdown with cleanup

**Actions:**

1. Log shutdown event
2. Stop all services
3. Kill running emulators
4. Sync Syncthing
5. Unmount USB storage
6. Trigger stage2 poweroff

**Usage:**

```bash
graceful_shutdown
```

### Archive Unpacking Functions (archiveUnpacker.sh)

#### `finish_unpacking()`

**Purpose:** Unpack pre-queued archive files

**Usage:**

```bash
finish_unpacking
# Processes any pending .zip or .7z files before menu launch
```

### First Boot Functions (firstboot.sh)

#### `run_first_boot_setup()`

**Purpose:** Initialize system on first boot

**Tasks:**

- Generate SSH keys
- Extract PortMaster bundle
- Extract ScummVM games
- Set initial configuration
- Create necessary directories

**Usage:**

```bash
run_first_boot_setup
```

### Swap Management Functions (set_up_swap.sh)

#### `create_swapfile(size)`

**Purpose:** Create swapfile with specified size

**Parameters:**

- `size` - Size in MB (128, 256, 512)

**Usage:**

```bash
create_swapfile 256    # Create 256MB swapfile
```

#### `enable_swapfile()`

**Purpose:** Enable the swapfile

**Usage:**

```bash
enable_swapfile
```

#### `disable_swapfile()`

**Purpose:** Disable and remove swapfile

**Usage:**

```bash
disable_swapfile
```

### ZRAM Management Functions (enable_zram.sh, disable_zram.sh)

#### `enable_zram_compression(algorithm)`

**Purpose:** Enable ZRAM memory compression

**Parameters:**

- `algorithm` - Compression method: "lz4" or "lzo"

**Usage:**

```bash
enable_zram_compression "lz4"
# Memory compression now active
```

#### `disable_zram_compression()`

**Purpose:** Disable ZRAM compression

**Usage:**

```bash
disable_zram_compression
```

## Configuration Functions

### RetroArch Configuration (retroarch_utils.sh)

#### `update_ra_config_file_with_new_setting(config_file setting value)`

**Purpose:** Update a RetroArch configuration setting

**Parameters:**

- `config_file` - Path to RetroArch .cfg file
- `setting` - Configuration key name
- `value` - New value

**Usage:**

```bash
update_ra_config_file_with_new_setting \
  "/mnt/SDCARD/RetroArch/retroarch.cfg" \
  "video_scale_integer" \
  "true"
```

### Settings Application Functions (applySetting/\*.sh)

#### `apply_perfect_overlays()`

**Purpose:** Apply Perfect Overlays to Game Boy systems

**Usage:**

```bash
apply_perfect_overlays
# GB, GBC, GBA now have enhanced overlays
```

#### `apply_cpu_settings()`

**Purpose:** Apply CPU governor settings from configuration

**Usage:**

```bash
apply_cpu_settings
```

#### `apply_display_settings()`

**Purpose:** Apply display brightness and resolution settings

**Usage:**

```bash
apply_display_settings
```

## Function Naming Conventions

### Device Functions

All device-specific files implement this pattern:

```bash
# In: platform/device_functions/<DEVICE>.sh
get_<function_name>()      # Retrieve/read operation
set_<function_name>()      # Change/write operation
```

### Emulator Functions

```bash
# In: emu/lib/<EMULATOR>_functions.sh
launch_<emulator>_<system>()        # Start emulator
load_<emulator>_configs()           # Load configuration
save_<emulator>_configs()           # Save state
get_<emulator>_core_for_<system>()  # Retrieve core mapping
```

### Network Functions

```bash
# In: network/<SERVICE>Functions.sh
start_<service>_process()    # Start service daemon
stop_<service>_process()     # Stop service daemon
generate_<service>_config()  # Create initial config (Syncthing)
repair_<service>_config()    # Fix corrupted config (Syncthing)
```

### Watchdog Functions

```bash
# In: *_watchdog.sh
detect_<event>()             # Monitor and detect event
handle_<event>()             # React to detected event
```

## Best Practices for Function Usage

1. **Always source helper functions first**: Most scripts depend on `helperFunctions.sh`
2. **Use consistent error handling**: Check return codes and log errors
3. **Avoid hardcoded paths**: Use provided `$*_DIR` variables
4. **Use functions instead of duplicating code**: Reduces maintenance burden
5. **Document function purpose and parameters**: Add header comments to new functions
6. **Return appropriate exit codes**: 0 for success, non-zero for failure
7. **Use `local` keyword** in functions to avoid global variable pollution
8. **Test on all supported platforms** before deploying new functions

## Function Dependency Graph

```
helperFunctions.sh (base - sourced by most)
├── device_functions.sh
│   └── platform/device_functions/*.sh
├── emu/lib/general_functions.sh
│   ├── emu/lib/core_mappings.sh
│   └── emu/lib/*_functions.sh
├── network/*Functions.sh
├── applySetting/*.sh
└── tasks/*.sh
```

For any function requiring device-specific behavior, ensure both:

1. Generic implementation in helper functions
2. Platform-specific override in platform-specific files
