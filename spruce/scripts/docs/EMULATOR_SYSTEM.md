# Emulator System Documentation

This document describes the universal emulator launching system in SpruceOS, which routes game launches to appropriate emulators using a flexible, configuration-driven architecture.

## Table of Contents

1. [System Overview](#system-overview)
2. [Architecture](#architecture)
3. [Emulator Launch Flow](#emulator-launch-flow)
4. [Emulator-Specific Handlers](#emulator-specific-handlers)
5. [Configuration System](#configuration-system)
6. [Core Mappings](#core-mappings)
7. [Adding New Emulators](#adding-new-emulators)
8. [Configuration Reference](#configuration-reference)

## System Overview

The emulator system provides:

1. **Universal Launcher** - Single entry point for all game launches
2. **Configuration-Driven Core Selection** - Cores selected from system JSON
3. **Platform Abstraction** - Works across all device types and architectures
4. **Modular Emulator Support** - Add new emulators without modifying core code
5. **Pre-Game and Post-Game Hooks** - Setup and cleanup around emulation

### Design Philosophy

Instead of having separate launch scripts for each emulator/system combination, SpruceOS uses a single `standard_launch.sh` that:

1. Detects which emulator is needed (from script filename)
2. Loads emulator-specific configuration from JSON
3. Routes to appropriate emulator handler
4. Cleans up after game session

This reduces code duplication and makes maintenance easier.

## Architecture

### Directory Structure

```
spruce/scripts/emu/
├── standard_launch.sh              # Universal launcher (entry point)
└── lib/
    ├── core_mappings.sh            # RetroArch core lookup table
    ├── general_functions.sh        # Universal emulator functions
    ├── ra_functions.sh             # RetroArch-specific
    ├── drastic_functions.sh        # NDS (DraStic) emulator
    ├── ppsspp_functions.sh         # PSP (PPSSPP) emulator
    ├── media_functions.sh          # Media playback (FFmpeg)
    ├── scummvm_functions.sh        # ScummVM adventure games
    ├── flycast_functions.sh        # DC/Naomi (Flycast)
    ├── mupen_functions.sh          # N64 (Mupen64plus)
    ├── pico8_functions.sh          # PICO-8 fantasy console
    ├── ports_functions.sh          # Game Ports (custom)
    ├── yaba_functions.sh           # Saturn (Yabasanshiro)
    ├── openbor_functions.sh        # Beat-em-up engine
    ├── led_functions.sh            # LED effects
    ├── network_functions.sh        # In-game network services
    └── gtt_functions.sh            # Game Time Tracking
```

### How Games Are Launched

1. **User selects game** in PyUI/MainUI
2. **Menu creates task** `/tmp/cmd_to_run.sh` with ROM path
3. **principal.sh detects file** and executes it
4. **Script path encodes system** (e.g., `/Emu/GB/launch.sh → GB system)
5. **standard_launch.sh sources** emulator-specific handler library
6. **Handler detects core** from system JSON configuration
7. **Handler launches game** with appropriate emulator
8. **On exit:** Cleanup and return to menu

### Game ROM Location Mapping

```
/Emu/<SYSTEM>/launch.sh
    ↓
standard_launch.sh determines EMU_NAME = <SYSTEM>
    ↓
Looks up core in: Emu/.emu_setup/<SYSTEM>/config.json
    ↓
Routes to appropriate emulator function
    ↓
Emulator reads ROM from: /mnt/SDCARD/Roms/<SYSTEM>/<GAME_FILE>
```

## Emulator Launch Flow

### Step-by-Step Execution

```
1. User selects game in menu
   ↓
2. Menu writes: /tmp/cmd_to_run.sh with ROM path
   Example: /Emu/GB/launch.sh "/mnt/SDCARD/Roms/GB/Tetris.gb"
   ↓
3. principal.sh detects /tmp/cmd_to_run.sh and executes it
   ↓
4. /Emu/GB/launch.sh is actually symlink to standard_launch.sh
   standard_launch.sh "${@}"
   ↓
5. standard_launch.sh:
   a) Source helperFunctions.sh  (load platform detection)
   b) Detect EMU_NAME from $0 path → EMU_NAME="GB"
   c) Source general_functions.sh
   d) Set CPU to performance mode
   e) Check network needs - stop services if required
   f) Source emulator-specific library (ra_functions.sh for GB)
   g) Load configuration from system JSON
   h) Get core preference: RetroArch or specific emulator
   i) Trigger LED effect (gaming profile)
   j) Call handler function: launch_gb_game() with ROM path
   ↓
6. Emulator-specific handler (e.g., launch_gb_game()):
   a) Load emulator configuration for system/platform
   b) Apply overlays if enabled (Perfect Overlays for GB)
   c) Launch emulator with game ROM
   d) Wait for emulator to exit
   ↓
7. Post-execution cleanup:
   a) Restore CPU mode to default
   b) Sync filesystem
   c) Restore display/audio settings
   d) Return to principal.sh → back to menu
```

### Configuration Access During Launch

```bash
# Example: GB system launch

# 1. Get core preference
CORE=$(get_config_value '.menuOptions.Emulator_GB.selected')
# Returns: "snes9x" or "mgba" (user setting in UI)

# 2. Get platform-specific override (if exists)
CORE=$(get_config_value ".menuOptions.Emulator_GB_${PLATFORM}.selected")
# Returns: platform override or empty string

# 3. Fall back to system default
if [ -z "$CORE" ]; then
    CORE=$(get_emu_core_for_system "GB")
    # Returns: "mgba" (default for GB)
fi

# 4. Get system-specific config
SYSTEM_CONFIG="/Emu/GB/config.json"
RA_CONFIG="/Saves/GB/config/retroarch-${PLATFORM}.cfg"

# 5. Apply configuration
launch_game_with_core "$ROM_PATH" "$CORE"
```

## Emulator-Specific Handlers

### RetroArch Systems (Most Systems)

RetroArch is used for the majority of systems via `ra_functions.sh`:

**Supported Systems:** NES, SNES, Genesis, GB, GBC, GBA, N64, PSX, and 20+ others

**Core Selection:**

```bash
# From system JSON configuration
jq '.menuOptions.Emulator_GB.selected' /mnt/SDCARD/spruce/<PLATFORM>-system.json
# Returns: User's selected core (e.g., "mgba", "snes9x")

# Core-to-ROM mapping (core_mappings.sh)
get_ra_core_for_system "GB"
# Returns: "mgba" (sensible default if user hasn't configured)
```

**Launch Code Pattern:**

```bash
launch_ra_game() {
    local rom_path="$1"
    local system="$2"
    local core="$3"

    # Set up RetroArch
    $RETROARCH \
        --config "$RA_CONFIG" \
        -L "/mnt/SDCARD/RetroArch/cores/${core}_libretro.so" \
        "$rom_path"
}
```

### DraStic Handler (NDS Emulator)

Nintendo DS games use DraStic exclusively (superior performance on handheld):

**Handler File:** `emu/lib/drastic_functions.sh`

**Launch Flow:**

```bash
launch_nds_game() {
    rom_path="$1"

    # Load platform-specific launcher
    case "$PLATFORM_ARCHITECTURE" in
        armhf)
            /mnt/SDCARD/Emu/NDS/drastic32 "$rom_path"
            ;;
        aarch64)
            /mnt/SDCARD/Emu/NDS/drastic64 "$rom_path"
            ;;
    esac
}
```

**Configuration:** Uses platform-specific `.cfg` files in `/Saves/NDS/`.

### PPSSPP Handler (PSP Emulator)

PlayStation Portable games use PPSSPP specifically:

**Handler File:** `emu/lib/ppsspp_functions.sh`

**Launch Flow:**

```bash
launch_psp_game() {
    rom_path="$1"

    # Platform-specific config
    case "$PLATFORM" in
        A30)
            PPSSPP_CONFIG="/Saves/PSP/A30_PPSSPPConfig.ini"
            ;;
        Flip)
            PPSSPP_CONFIG="/Saves/PSP/Flip_PPSSPPConfig.ini"
            ;;
    esac

    PPSSPP_CONFIG_DIR="$(dirname "$PPSSPP_CONFIG")"

    /mnt/SDCARD/Emu/PSP/PPSSPP_Core \
        --config-dir="$PPSSPP_CONFIG_DIR" \
        "$rom_path"
}
```

### ScummVM Handler (Adventure Games)

Point-and-click adventure games use ScummVM:

**Handler File:** `emu/lib/scummvm_functions.sh`

**Game Discovery:**

```bash
scan_scummvm_library() {
    /mnt/SDCARD/Emu/SCUMMVM/scummvm --list-games | \
        awk '{print $1}' | \
        head -n -1
}
```

**Launch Flow:**

```bash
launch_scummvm_game() {
    game_id="$1"

    /mnt/SDCARD/Emu/SCUMMVM/scummvm \
        --config=/etc/scummvmrc \
        --savepath=/mnt/SDCARD/Saves/SCUMMVM \
        "$game_id"
}
```

### Media Handler (FFmpeg)

Video and media files use FFmpeg for playback:

**Handler File:** `emu/lib/media_functions.sh`

**Launch Flow:**

```bash
launch_media_file() {
    media_path="$1"

    ffplay -fs "$media_path"  # Full-screen playback
}
```

### Custom Ports Handler

Game ports use platform-specific launchers:

**Handler File:** `emu/lib/ports_functions.sh`

**Launch Flow:**

```bash
launch_port_game() {
    port_name="$1"

    case "$port_name" in
        doom)
            /mnt/SDCARD/App/A30PORTS/doom/doom.elf
            ;;
        quake)
            /mnt/SDCARD/App/A30PORTS/quake/quake
            ;;
    esac
}
```

### Special System Routing

**A30PORTS System:**

- Routes to appropriate port launcher
- Auto-detects port type
- May require platform-specific binary

**MEDIA/MOVIES System:**

- Routes to FFmpeg
- Handles video, audio, images
- Scales to display resolution

**DC/NAOMI Systems:**

- Uses Flycast emulator preferentially
- Falls back to RetroArch if Flycast unavailable

**PICO8 System:**

- Uses PICO-8 fantasy console binary
- Runs `.p8` cartridge files

## Configuration System

### System Configuration Files

Each system has its own configuration:

```
/Emu/GB/config.json              # User settings for Game Boy
/Emu/.emu_setup/GB/config.json   # Factory defaults for GB
/Saves/GB/config/                # Runtime-specific configs
/Saves/GB/<PLATFORM>.*.cfg       # Platform-specific backups
```

### Configuration Structure

```json
{
  "menuOptions": {
    "Emulator": {
      "selected": "mgba", // Global default core
      "options": ["snes9x", "mgba"] // Available cores
    },
    "Emulator_GB": {
      "selected": "mgba", // GB-specific override
      "options": ["snes9x", "mgba", "gb"] // GB available cores
    },
    "Emulator_GB_A30": {
      "selected": "gb", // A30-specific override for GB
      "options": ["gb"] // Limited to this on 32-bit
    },
    "GB_Settings": {
      "renderer": "software",
      "saveType": "automatic",
      "bootBIOS": false
    }
  }
}
```

### Configuration Precedence (For Core Selection)

```
1. User's platform-specific override:
   .menuOptions.Emulator_<SYSTEM>_<PLATFORM>.selected

2. User's system-specific preference:
   .menuOptions.Emulator_<SYSTEM>.selected

3. User's global emulator preference:
   .menuOptions.Emulator.selected

4. System default (hardcoded in core_mappings.sh):
   Default core for system
```

### Configuration Reading Functions

```bash
# Generic configuration reader
CORE=$(get_config_value '.menuOptions.Emulator_GB.selected')

# With jq directly
CORE=$(jq '.menuOptions.Emulator_GB.selected' "$SYSTEM_JSON")

# Emulator-specific reader (general_functions.sh)
set_emu_core_from_emu_json "GB"
echo "Using core: $CORE"
```

## Core Mappings

The `core_mappings.sh` file provides default core selections for each system:

```bash
# core_mappings.sh - Default RetroArch cores

get_ra_core_for_system() {
    local system="$1"

    case "$system" in
        # Nintendo Systems
        NES|FC)          echo "fceumm" ;;
        SNES|SFC)        echo "snes9x" ;;
        N64)             echo "mupen64plus" ;;  # Via ra_functions
        GBA)             echo "mgba" ;;
        GB|GBC)          echo "mgba" ;;

        # Sega Systems
        MD|GEN|GENESIS)  echo "genesis_plus_gx" ;;
        GG)              echo "genesis_plus_gx" ;;
        MS|MASTERSYSTEM) echo "genesis_plus_gx" ;;

        # Sony Systems
        PS)              echo "pcsx_rearmed" ;;

        # Atari Systems
        ATARI)           echo "stella" ;;

        # Arcade Systems
        ARCADE|CPS1|CPS2|NEOGEO) echo "fbneo" ;;

        # Other Systems
        PCECD|PCE)       echo "mednafen_pce" ;;
        SUPERGRAFX)      echo "mednafen_supergrafx" ;;

        *)               echo "snes9x" ;;  # Safe default
    esac
}
```

### Core Availability by System

```
NES/FC:              fceumm, nestopia, fceux
SNES/SFC:            snes9x, bsnes, mednafen_snes
Genesis/MD:          genesis_plus_gx, picodrive
N64:                 mupen64plus (via emu binary)
ARCADE:              fbneo, mame2003plus, fbalpha2012
PS1:                 pcsx_rearmed
PSX:                 mednafen_psx
GB/GBC:              mgba, gambatte
GBA:                 mgba, visualboyadvance
NDS:                 drastic (not RetroArch)
PSP:                 PPSSPP (not RetroArch)
DC/NAOMI:            Flycast (preferred) or fbneo
```

## Adding New Emulators

### Step 1: Create Emulator Function Library

Create `emu/lib/newemu_functions.sh`:

```bash
#!/bin/bash
# emu/lib/newemu_functions.sh
# NewEmulator-specific functions

# Required: main launch function
launch_newemu_game() {
    local rom_path="$1"

    # Load configuration
    source "${SCRIPT_DIR}/emu/lib/general_functions.sh"

    # Get core/renderer preference
    local emulator_config="/Saves/SYSTEM/config.json"
    local renderer=$(jq '.settings.renderer.selected' "$emulator_config")

    # Launch emulator
    /path/to/newemu \
        --config=/etc/newemu.conf \
        --renderer="$renderer" \
        "$rom_path"
}

# Optional: cleanup function
cleanup_newemu() {
    # Kill any remaining processes
    pkill -f newemu || true
}

# Optional: save state function
save_newemu_state() {
    # Save game state for autoresume
}
```

### Step 2: Update standard_launch.sh Router

Edit in `emu/standard_launch.sh`:

```bash
# Add to emulator detection switch
case "$EMU_NAME" in
    NewSystem)
        source "${SCRIPT_DIR}/emu/lib/newemu_functions.sh"
        launch_newemu_game "$ROM_PATH"
        ;;
    # ... existing cases
esac
```

### Step 3: Create System Directory

```bash
mkdir -p /Emu/NEWSYSTEM
mkdir -p /Emu/.emu_setup/NEWSYSTEM
mkdir -p /Saves/NEWSYSTEM/config
```

### Step 4: Create Symbolic Link

```bash
ln -s /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh \
      /mnt/SDCARD/Emu/NEWSYSTEM/launch.sh
```

### Step 5: Add Configuration Files

Create `/Emu/.emu_setup/NEWSYSTEM/config.json`:

```json
{
  "menuOptions": {
    "Emulator_NEWSYSTEM": {
      "selected": "newemu_core",
      "options": ["newemu_core", "other_core"]
    }
  }
}
```

### Step 6: Test

```bash
# Test rom launching
/Emu/NEWSYSTEM/launch.sh "/mnt/SDCARD/Roms/NEWSYSTEM/game.rom"
```

## Configuration Reference

### Standard Launch Options

```bash
# Via command line
/Emu/GB/launch.sh "/mnt/SDCARD/Roms/GB/game.gb"

# Via configuration file
CONFIG="/Saves/GB/config.json"
jq '.menuOptions.Emulator_GB.selected' "$CONFIG"
```

### Environment Variables Used During Launch

| Variable           | Set By               | Purpose                     |
| ------------------ | -------------------- | --------------------------- |
| `$PLATFORM`        | helperFunctions.sh   | Device model                |
| `$EMU_NAME`        | standard_launch.sh   | Detected system             |
| `$CORE`            | general_functions.sh | Selected core/emulator      |
| `$ROM_PATH`        | (argument)           | Game file path              |
| `$RETROARCH`       | (detected)           | RetroArch binary path       |
| `$LD_LIBRARY_PATH` | (set per emu)        | Emulator-specific libraries |

### Pre-Launch Setup

These functions run before emulator launch:

```bash
set_performance             # Set CPU to max
led_effect_gaming          # LED gaming mode
stop_network_services      # Free up resources (optional)
start_network_services     # Resume services on exit
```

### Post-Launch Cleanup

These functions run after emulator exit:

```bash
set_smart                  # Return to balanced CPU
led_effect_off             # Turn off LED effects
log_game_end               # Record playtime
start_network_services     # Resume services
```

## Troubleshooting

### Game Won't Launch

1. Check ROM path exists: `/mnt/SDCARD/Roms/<SYSTEM>/<GAME>`
2. Verify system JSON has core setting: `jq '.menuOptions.Emulator_<SYSTEM>.selected' "$SYSTEM_JSON"`
3. Check emulator binary exists: `ls /mnt/SDCARD/Emu/<SYSTEM>/`
4. Check library exists: `ls /mnt/SDCARD/RetroArch/cores/<CORE>_libretro.so`

### Wrong Emulator Launched

1. Check system JSON preference: `get_config_value '.menuOptions.Emulator_<SYSTEM>.selected'`
2. Verify core exists for platform
3. Check core_mappings.sh has entry for system

### Game Runs But Controls Don't Work

1. Check button mapping in platform-specific retroarch.cfg
2. Verify RetroArch port of launch has input overlay enabled
3. Check device button codes in platform/\*.cfg

### Game Crashes on Exit

1. Check emulator cleanup code in handler
2. Verify no orphan processes: `ps aux | grep emu`
3. Check filesystem sync: `sync` before exit
