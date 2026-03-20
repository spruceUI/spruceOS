# SpruceOS Scripts Documentation

## Overview

The `scripts` directory contains a comprehensive collection of shell scripts that power SpruceOS functionality across all supported devices (Miyoo A30, Miyoo Mini, Miyoo Flip, TrimUI SmartPro, TrimUI Brick, and TrimUI SmartProS). These scripts handle system initialization, emulator launching, device hardware abstraction, power management, network services, and user interface control.

## Directory Structure

```
spruce/scripts/
├── System Management
│   ├── runtime.sh                 # System startup initialization
│   ├── runtimeHelper.sh          # Runtime helper utilities
│   ├── principal.sh              # Main control loop and game switching
│   ├── firstboot.sh              # First-boot setup
│   ├── archiveUnpacker.sh        # Archive unpacking service
│   ├── enable_zram.sh            # Enable ZRAM compression
│   ├── disable_zram.sh           # Disable ZRAM
│   ├── set_up_swap.sh            # Swapfile management
│   └── enforceSmartCPU.sh        # CPU governor locking
│
├── Watchdog & Monitoring
│   ├── powerbutton_watchdog.sh   # Power button monitoring (v1)
│   ├── power_button_watchdog_v2.sh # Power button handling (v2)
│   ├── buttons_watchdog.sh       # Brightness and button mapping
│   ├── homebutton_watchdog.sh    # Home button actions
│   ├── lid_watchdog_v2.sh        # Lid sensor monitoring
│   ├── bluetooth_watchdog.sh     # Bluetooth monitoring
│   └── mixer_watchdog.sh         # Audio mixer watchdog
│
├── Power Management
│   ├── idlemon_chargingAction.sh  # Idle charging action
│   ├── idlemon_poweroffAction.sh  # Idle poweroff wrapper
│   ├── sleep_helper.sh            # Sleep/suspend handler
│   ├── low_power_warning.sh       # Battery warning system
│   ├── save_poweroff.sh           # Graceful shutdown
│   └── save_poweroff_stage2.sh    # Final unmounting
│
├── Audio & Display
│   ├── asound-setup.sh            # Bluetooth audio configuration
│   ├── audioFunctions.sh          # Audio control (deprecated)
│   ├── autoIconRefresh.sh         # Theme change watcher
│   ├── iconfresh.sh               # Icon/theme refresh
│   └── retroarch_utils.sh         # RetroArch configuration updates
│
├── Network Services
│   ├── networkservices.sh         # Main network orchestrator
│   └── (Network function libraries - see below)
│
├── Emulator Control
│   ├── emu/
│   │   └── standard_launch.sh    # Universal emulator launcher
│   └── emu/lib/
│       ├── (Emulator-specific functions - see below)
│
├── Platform Abstraction
│   ├── platform/
│   │   ├── *.cfg                 # Platform configuration files
│   │   ├── device.sh             # Device detection script
│   │   └── device_functions/
│   │       ├── *.sh              # Platform-specific device functions
│   │       └── utils/            # Device utility scripts
│   └── applySetting/
│       ├── *.sh                  # Settings application scripts
│
└── Tasks & Utilities
    ├── tasks/
    │   ├── bugReport.sh          # Bug report generator
    │   ├── clearwifi.sh          # WiFi clearing utility
    │   ├── deleteMacFiles.sh     # macOS artifact removal
    │   ├── repairSD.sh           # SD card repair
    │   ├── resetNDS.sh           # Reset NDS configuration
    │   ├── resetPPSSPP.sh        # Reset PSP configuration
    │   ├── resetRA.sh            # Reset RetroArch
    │   ├── resetRAHotkeys.sh     # Reset RetroArch hotkeys
    │   └── scanScummVM.sh        # ScummVM game discovery
    │
    └── Support Libraries
        ├── helperFunctions.sh    # Core helper functions
        ├── device_functions.sh   # Device abstraction layer
        └── network/
            ├── sshFunctions.sh
            ├── sambaFunctions.sh
            ├── syncthingFunctions.sh
            ├── sftpgoFunctions.sh
            └── darkhttpdFunctions.sh
```

## Script Categories

### 1. **System Management & Runtime** (9 scripts)

| Script               | Purpose                       | Main Functionality                                             |
| -------------------- | ----------------------------- | -------------------------------------------------------------- |
| `runtime.sh`         | System startup initialization | Logging setup, WiFi, swap, firmware checks, watchdog launching |
| `runtimeHelper.sh`   | Runtime utilities             | SD card fixes, firmware app visibility, OTA checks             |
| `principal.sh`       | Main control loop             | Game switching, PyUI launch, emulator execution manager        |
| `firstboot.sh`       | First-boot setup              | SSH setup, PortMaster/ScummVM extraction, version detection    |
| `archiveUnpacker.sh` | Archive unpacking             | Pre-menu and pre-command archive unpacking                     |
| `enable_zram.sh`     | Memory compression            | ZRAM device setup with lz4/lzo compression                     |
| `disable_zram.sh`    | Disable ZRAM                  | Swap disable and device reset                                  |
| `set_up_swap.sh`     | Swap file management          | Create/manage swapfile (128-512MB)                             |
| `enforceSmartCPU.sh` | CPU governor locking          | Prevent CPU mode changes during execution                      |

### 2. **Watchdog & Monitoring Processes** (7 scripts)

Continuous background processes that monitor hardware events and system state:

| Script                             | Event Triggers      | Actions                                            |
| ---------------------------------- | ------------------- | -------------------------------------------------- |
| `powerbutton_watchdog.sh` (v1)     | Power button press  | Wake alarm configuration, emulator detection       |
| `power_button_watchdog_v2.sh` (v2) | Power press/release | Sleep trigger on press, poweroff on 2s hold        |
| `buttons_watchdog.sh`              | Button combinations | System brightness mapping (10 levels)              |
| `homebutton_watchdog.sh`           | Home button press   | DraStic pause/resume, port termination, screenshot |
| `lid_watchdog_v2.sh`               | Lid open/close      | Sleep on close (with charging state checks)        |
| `bluetooth_watchdog.sh`            | Config changes      | Enable Bluetooth/bluealsa                          |
| `mixer_watchdog.sh`                | Audio events        | Call audio control routines                        |

### 3. **Power Management** (6 scripts)

| Script                      | Purpose             | Triggers                                        |
| --------------------------- | ------------------- | ----------------------------------------------- |
| `idlemon_chargingAction.sh` | Idle while charging | Screen off when charging, wake on input         |
| `idlemon_poweroffAction.sh` | Idle poweroff       | Route to save_poweroff.sh for inactive apps     |
| `sleep_helper.sh`           | Sleep/suspend       | Manage lid/power button, wakeup timers          |
| `low_power_warning.sh`      | Battery warning     | Morse code SOS LED/vibration, battery logging   |
| `save_poweroff.sh`          | Graceful shutdown   | Syncthing sync, process cleanup, stage2 trigger |
| `save_poweroff_stage2.sh`   | Final cleanup       | Minimal unmounting with reduced binaries        |

### 4. **Network Services** (1 main + 5 function libraries)

The network subsystem uses a modular architecture:

```
networkservices.sh (main orchestrator)
├── sshFunctions.sh          (SSH/Dropbear)
├── sambaFunctions.sh        (SMB/Samba)
├── syncthingFunctions.sh    (Syncthing sync)
├── sftpgoFunctions.sh       (SFTP server)
└── darkhttpdFunctions.sh    (HTTP server)
```

**Startup Flow:**

1. Wait for WiFi connection
2. Check Samba config → start/stop
3. Check SSH config → start/stop
4. Check SFTPGo config → start/stop
5. Check Syncthing config → start/stop
6. Auto-setup Darkhttpd

### 5. **Emulator Launch System** (1 main + 16 function libraries)

The emulator system uses a universal launcher that routes to emulator-specific handlers:

**Main Coordinator:**

- `emu/standard_launch.sh` - Universal emulator launcher

**Emulator-Specific Libraries:**

```
emu/lib/
├── core_mappings.sh          # RetroArch core-to-folder mapping
├── general_functions.sh      # Universal emulator functions
├── ra_functions.sh           # RetroArch-specific
├── drastic_functions.sh      # NDS (DraStic) emulator
├── ppsspp_functions.sh       # PSP (PPSSPP) emulator
├── media_functions.sh        # Media playback (FFmpeg)
├── scummvm_functions.sh      # ScummVM adventure games
├── flycast_functions.sh      # Dreamcast/Naomi (Flycast)
├── mupen_functions.sh        # N64 (Mupen64plus)
├── pico8_functions.sh        # PICO-8 fantasy console
├── ports_functions.sh        # Custom game ports
├── yaba_functions.sh         # Sega Saturn (Yabasanshiro)
├── openbor_functions.sh      # Beat-em-up engine (OpenBOR)
├── led_functions.sh          # LED effects during gameplay
├── network_functions.sh      # In-game network services
└── gtt_functions.sh          # Game Time Tracking
```

**Emulator Launch Flow:**

1. Source helper functions and platform-specific code
2. Detect emulator from script path (EMU_NAME)
3. Load CPU mode from configuration
4. Set CPU mode via platform-specific handler
5. Initialize network services if needed
6. Trigger LED effects
7. Route to appropriate emulator:
   - A30PORTS → A30 port launcher
   - DC/NAOMI → Flycast or RetroArch
   - GB/GBC/GBA → Perfect Overlays + RetroArch
   - MEDIA → FFplay or RetroArch
   - NDS → DraStic
   - PSP → PPSSPP
   - SCUMMVM → ScummVM Menu/Play
   - Other systems → RetroArch
8. Post-execution cleanup and settings restoration

### 6. **Platform Abstraction Layer**

The platform layer ensures device-agnostic script design through hardware abstraction:

**Device Detection (via `/proc/cpuinfo`):**

- `sun8i` → Miyoo A30 (32-bit)
- `TG5040` → TrimUI SmartPro
- `TG3040` → TrimUI Brick
- `TG5050` → TrimUI SmartProS
- `0xd05` → Miyoo Flip
- `0xd04` → Miyoo Pixel2
- Default → Miyoo Mini

**Platform-Specific Functions:**

```
platform/device_functions/
├── A30.sh                    # Miyoo A30 (32-bit)
├── MiyooMini.sh              # Miyoo Mini (32-bit)
├── Flip.sh                   # Miyoo Flip (64-bit)
├── SmartPro.sh               # TrimUI SmartPro (64-bit)
├── SmartProS.sh              # TrimUI SmartProS (64-bit)
├── Pixel2.sh                 # Miyoo Pixel2 (64-bit)
├── Brick.sh                  # TrimUI Brick (64-bit)
├── common32bit.sh            # Shared 32-bit code
├── common64bit.sh            # Shared 64-bit code
└── utils/
    ├── cpu_control_functions.sh    # CPU frequency scaling
    ├── watchdog_launcher.sh        # Watchdog spawning
    ├── legacy_display.sh           # Display wrappers
    ├── rumble.sh                   # GPIO vibration
    ├── sleep_functions.sh          # Sleep handlers
    ├── flip_a30_brightness.sh      # Brightness control
    ├── miyoomini/mm_set_volume.py  # Volume control (Python)
    └── smartpros/adaptive_fan.py   # Fan control (TrimUI)
```

### 7. **Task & Utility Scripts** (9 scripts)

Located in `tasks/` directory:

| Script              | Purpose                                      |
| ------------------- | -------------------------------------------- |
| `bugReport.sh`      | Collect logs and configs into 7z archive     |
| `clearwifi.sh`      | Remove all WiFi networks                     |
| `deleteMacFiles.sh` | Remove macOS artifacts (.DS_Store, .Trashes) |
| `repairSD.sh`       | SD card repair utility with fsck             |
| `resetNDS.sh`       | Restore NDS configuration from backups       |
| `resetPPSSPP.sh`    | Restore PSP emulator configuration           |
| `resetRA.sh`        | Restore RetroArch to baseline config         |
| `resetRAHotkeys.sh` | Reset RetroArch hotkeys to defaults          |
| `scanScummVM.sh`    | Discover ScummVM games automatically         |

## Critical Process Flows

### Game Launch Sequence

```
1. User selects game in MainUI
2. MainUI writes: /tmp/cmd_to_run.sh
3. MainUI exits → principal.sh detects file
4. principal.sh:
   - Sets performance CPU mode
   - Saves command to /mnt/SDCARD/spruce/flags/lastgame.lock (autoresume)
   - Executes /tmp/cmd_to_run.sh (symlink to /Emu/<SYSTEM>/launch.sh)
5. standard_launch.sh router calls appropriate emulator
6. Emulator runs with saved configurations
7. On exit:
   - Restores CPU mode
   - Syncs filesystem
   - Returns to principal.sh loop
```

### Shutdown Sequence

```
save_poweroff.sh:
  1. Logs activity event
  2. Stops all background services
  3. Kills running emulators/MainUI
  4. Saves Syncthing data
  5. Unmounts USB storage if mounted
  6. Copies stage2 to /tmp/
  7. Executes stage2 with minimal PATH
       ↓
save_poweroff_stage2.sh:
  1. Uses only: /usr/bin, /usr/sbin, /bin, /sbin
  2. Finds all processes with open SD files
  3. Kills them (SIGKILL)
  4. Waits for kernel cleanup
  5. Unmounts SD card
  6. Poweroff or reboot
```

### Sleep/Lid Sensor Sequence

```
lid_watchdog_v2.sh (continuous):
  1. Monitor lid state via device_lid_open()
  2. Check setting: True/False/"Only when unplugged"
  3. On close + condition met:
       ↓
sleep_helper.sh:
  1. Logs current app activity STOP
  2. Creates sleep_helper_started marker
  3. Monitors power button via getevent
  4. Waits for shutdown timer (config-driven: 2m-60m)
  5. On timeout:
       → save_poweroff.sh
  6. On power press before timeout:
       → Resume game/app
```

## Configuration & Settings Management

### Settings JSON Structure

The main configuration file (`/mnt/SDCARD/spruce/<PLATFORM>-system.json`) contains:

```json
{
  "menuOptions": {
    "System Settings": {
      "swapfileSize": { "selected": "256MB" },
      "useZRAM": { "selected": "False" },
      "overclockSpeedA30": { "selected": "1344" },
      "rumbleIntensity": { "selected": "Medium" },
      "enableLidSensor": { "selected": "True" },
      "checkForUpdates": { "selected": "True" }
    },
    "Network Settings": {
      "enableSamba": { "selected": "False" },
      "enableSSH": { "selected": "False" },
      "enableSFTPGo": { "selected": "False" },
      "enableSyncthing": { "selected": "False" }
    },
    "Emulator Settings": {
      "raAutoSave": { "selected": "Custom" },
      "raAutoLoad": { "selected": "Custom" },
      "perfectOverlays": { "selected": "False" }
    },
    "Battery Settings": {
      "shutdownFromSleep": { "selected": "5m" }
    }
  },
  "theme": "SPRUCE",
  "wifi": 0
}
```

### Configuration Hierarchy (Emulators)

```
/Emu/<SYSTEM>/config.json         → User settings per system
/Emu/.emu_setup/                  → Factory defaults
/Emu/<SYSTEM>/config/             → Runtime configs (platform-specific)
/Saves/<SYSTEM>/config/           → User-modified configs
/Saves/<SYSTEM>/<PLATFORM>.*.cfg  → Platform-specific backups
```

## Key Dependencies & Sourcing Chains

### Initialization Chain (Runtime Startup)

```
runtime.sh
  ├── helperFunctions.sh
  │   ├── platform/$PLATFORM.cfg (hardware definitions)
  │   └── device_functions.sh
  │       └── platform/$PLATFORM.sh
  │           └── platform/device_functions/utils/*.sh
  └── runtimeHelper.sh
      ├── sambaFunctions.sh
      └── sshFunctions.sh
```

### Emulator Launch Chain

```
/Emu/<SYSTEM>/launch.sh → standard_launch.sh
  ├── helperFunctions.sh
  ├── emu/lib/general_functions.sh
  │   ├── core_mappings.sh
  │   └── emu/lib/<EMULATOR>_functions.sh
  ├── emu/lib/led_functions.sh
  ├── emu/lib/network_functions.sh
  └── emu/lib/gtt_functions.sh
```

### Main Menu Cycle Chain

```
principal.sh
  ├── helperFunctions.sh
  ├── archiveUnpacker.sh → finish_unpacking()
  ├── firstboot.sh (conditional)
  └── /tmp/cmd_to_run.sh → emulator launch chain
```

## Cross-Script Communication

### Flag System

Temporary state markers stored in `/mnt/SDCARD/spruce/flags/`:

```bash
flag_add "name" [--tmp]          # Create flag file (--tmp = /tmp)
flag_check "name"                # Test flag existence
flag_remove "name"               # Delete flag

# Common flags:
silentUnpacker, first_boot_$PLATFORM, in_menu, lastgame.lock,
low_battery, perfectOverlays, log_verbose, pb.longpress
```

### Temporary Files (Inter-Process Communication)

| File                        | Purpose                              |
| --------------------------- | ------------------------------------ |
| `/tmp/cmd_to_run.sh`        | Command passed from menu to launcher |
| `/tmp/powerbtn`             | Power button state marker            |
| `/tmp/sleep_helper_started` | Sleep mode active marker             |
| `/tmp/host_msg`             | Network broadcast message            |

### Log Files

| Path                                       | Purpose                |
| ------------------------------------------ | ---------------------- |
| `/var/log/messages`                        | System event log       |
| `/mnt/SDCARD/Saves/spruce/spruce.log`      | Main application log   |
| `/mnt/SDCARD/Saves/spruce/*.log`           | Emulator-specific logs |
| `/mnt/SDCARD/Saves/spruce/battery_log.txt` | Battery history        |

## Documentation Reference

For detailed information about specific topics, see:

- **[FUNCTIONS.md](FUNCTIONS.md)** - Complete function reference for all scripts
- **[ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md)** - Environment variables used across scripts
- **[PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md)** - Platform-specific implementations
- **[EMULATOR_SYSTEM.md](EMULATOR_SYSTEM.md)** - Emulator launch and configuration system
- **[NETWORK_SERVICES.md](NETWORK_SERVICES.md)** - Network service configuration and management

## Related Directories

- **`/Emu/`** - Emulator installations and per-system configurations
- **`/Roms/`** - Game ROM storage organized by system
- **`/Saves/`** - Game saves, configurations, and screenshots
- **`/RetroArch/`** - RetroArch persistent configurations
- **`/Themes/`** - UI theme files and resources
- **`/App/`** - Utility applications

## Notes for Developers

1. **Always source `helperFunctions.sh` first** in scripts that need device detection or platform-specific code
2. **Use the flag system** for inter-process communication instead of temporary files when possible
3. **Platform-specific code** should be isolated in `platform/device_functions/` files
4. **Configuration values** are accessed via `get_config_value '.path.to.setting'` helper function
5. **Logging** should use the established log rotation and verbosity system
6. **Emulator setup** is handled by `standard_launch.sh`; don't replicate emulator-specific code in individual scripts

## Support

For issues or questions about specific script functionality, refer to the detailed documentation files listed above or examine the script source code with comments.
