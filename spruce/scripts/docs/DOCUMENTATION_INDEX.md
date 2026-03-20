# SpruceOS Scripts Documentation Index

## Quick Start

Welcome to the SpruceOS scripts documentation! This is a comprehensive guide to understanding and working with the SpruceOS runtime system.

### For First Time Users

1. Start with [README.md](README.md) for an overview of the directory structure and key concepts
2. Review [PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md) to understand how scripts work across devices
3. Consult [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) when scripts need device-specific data

### For Developers

1. [FUNCTIONS.md](FUNCTIONS.md) - Complete function reference for all available functions
2. [EMULATOR_SYSTEM.md](EMULATOR_SYSTEM.md) - Understanding how games are launched and routed to emulators
3. [NETWORK_SERVICES.md](NETWORK_SERVICES.md) - Reference for network functionality

## Documentation Files

### 1. **README.md** - Complete System Overview

**Best for:** Understanding the big picture

Contents:

- Directory structure and organization
- Script categories and purposes
- Critical process flows (game launch, shutdown, sleep)
- Configuration and settings management
- Cross-script communication patterns
- Related directories

**Read this when:** You want to understand what each script does and how they interact

---

### 2. **ENVIRONMENT_VARIABLES.md** - Environment Variable Reference

**Best for:** Understanding hardware abstraction and configuration

Contents:

- System configuration variables ($PLATFORM, $SYSTEM_JSON)
- Hardware path variables (input devices, display, LED)
- Button mapping variables
- Directory and path variables
- State and flag variables
- Cross-script usage patterns
- Platform-specific variable sets

**Read this when:** You need to know what variables are available or how to access settings

---

### 3. **FUNCTIONS.md** - Function Reference

**Best for:** Learning about available functions

Contents:

- Helper functions (device detection, configuration, logging)
- Device control functions (CPU, display, LED, vibration)
- Emulator control functions
- Network service functions
- Watchdog functions
- System management functions
- Configuration functions

**Read this when:** You want to know what a function does or how to call it

---

### 4. **PLATFORM_ABSTRACTION.md** - Platform Layer Documentation

**Best for:** Understanding device abstraction and cross-device compatibility

Contents:

- Platform detection mechanism
- Three-layer abstraction model
- Platform configuration files
- Device-specific function implementations
- Implementation examples
- Adding support for new devices
- Platform capability matrix

**Read this when:** You want to understand how to write device-agnostic code

---

### 5. **EMULATOR_SYSTEM.md** - Emulator Launch System

**Best for:** Understanding game launching and emulator routing

Contents:

- System overview and design philosophy
- Architecture and directory structure
- Step-by-step launch flow
- Emulator-specific handlers
- Configuration system
- Core mappings
- Adding new emulators
- Troubleshooting guide

**Read this when:** You need to understand how games are launched or add new emulator support

---

### 6. **NETWORK_SERVICES.md** - Network Services Reference

**Best for:** Setting up and troubleshooting network features

Contents:

- Network system overview
- Service architecture
- SSH (Dropbear) configuration and usage
- Samba (SMB) file sharing
- Syncthing sync setup
- SFTPGo SFTP server
- Darkhttpd HTTP server
- Configuration management
- Common tasks and troubleshooting

**Read this when:** You want to set up network services or troubleshoot connection issues

---

## Topic Guide

### I want to...

#### Understand How The System Works

1. [README.md](README.md#directory-structure) - Overview of structure
2. [README.md](README.md#script-categories) - What each script does
3. [README.md](README.md#critical-process-flows) - How games launch and shutdown

#### Write a New Script

1. [PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md) - Understand device abstraction
2. [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md) - Know what variables are available
3. [FUNCTIONS.md](FUNCTIONS.md) - See reusable functions
4. [README.md](README.md#key-dependencies--sourcing-chains) - Understand sourcing patterns

#### Add Support for a New Device

1. [PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md#adding-support-for-new-devices) - Step-by-step guide
2. platform configuration files as references
3. [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md#platform-specific-variable-sets) - Variable templates

#### Add a New Emulator

1. [EMULATOR_SYSTEM.md](EMULATOR_SYSTEM.md#adding-new-emulators) - Step-by-step guide
2. [EMULATOR_SYSTEM.md](EMULATOR_SYSTEM.md#emulator-specific-handlers) - Handler examples
3. Existing emulator handler files as templates

#### Set Up Network Services

1. [NETWORK_SERVICES.md](NETWORK_SERVICES.md) - Start here
2. [NETWORK_SERVICES.md](NETWORK_SERVICES.md#common-tasks) - Task reference
3. [NETWORK_SERVICES.md](NETWORK_SERVICES.md#troubleshooting) - Debugging

#### Debug a Script

1. [ENVIRONMENT_VARIABLES.md](ENVIRONMENT_VARIABLES.md#accessing-variables-in-scripts) - Check variable access
2. [FUNCTIONS.md](FUNCTIONS.md#logging-functions) - Use logging functions
3. Check `/mnt/SDCARD/Saves/spruce/spruce.log` for logs

#### Understand CPU/Performance

1. [PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md#device-specific-functions) - CPU control functions
2. [FUNCTIONS.md](FUNCTIONS.md#cpugovernor-functions-generic) - Generic CPU functions
3. [PLATFORM_ABSTRACTION.md](PLATFORM_ABSTRACTION.md#performance-implications) - Frequency table

#### Troubleshoot Boot Issues

1. [README.md](README.md#critical-process-flows) - Understand startup sequence
2. Check system logs: `/var/log/messages`
3. Check SpruceOS logs: `/mnt/SDCARD/Saves/spruce/spruce.log`

#### Troubleshoot Game Launch Issues

1. [EMULATOR_SYSTEM.md](EMULATOR_SYSTEM.md#troubleshooting) - Emulator debugging guide
2. Check game ROM path and format
3. Verify emulator core is installed

---

## Script Organization Summary

### By Function Category

| Category             | Key Files                                        | Purpose                              |
| -------------------- | ------------------------------------------------ | ------------------------------------ |
| **System Startup**   | runtime.sh, firstboot.sh, runtimeHelper.sh       | Initialize system and load services  |
| **Main Menu Loop**   | principal.sh, archiveUnpacker.sh                 | Game selection and launching         |
| **Game Launch**      | emu/standard_launch.sh, emu/lib/\*.sh            | Route to emulator and launch         |
| **Watchdogs**        | \*\_watchdog.sh                                  | Monitor hardware events continuously |
| **Power Management** | save*poweroff.sh, sleep_helper.sh, idlemon*\*.sh | Shutdown and idle handling           |
| **Device Control**   | platform/device_functions/\*.sh                  | Hardware abstraction layer           |
| **Network Services** | network/\*Functions.sh, networkservices.sh       | Connectivity and file sharing        |
| **Utilities**        | tasks/\*.sh                                      | System maintenance and repair        |

### By Device Support

| Device               | Architecture   | Config File   | Device File  |
| -------------------- | -------------- | ------------- | ------------ |
| **Miyoo A30**        | 32-bit (ARMv7) | A30.cfg       | A30.sh       |
| **Miyoo Mini**       | 32-bit (ARMv7) | MiyooMini.cfg | MiyooMini.sh |
| **Miyoo Flip**       | 64-bit (ARMv8) | Flip.cfg      | Flip.sh      |
| **TrimUI SmartPro**  | 64-bit (ARMv8) | SmartPro.cfg  | SmartPro.sh  |
| **TrimUI SmartProS** | 64-bit (ARMv8) | SmartProS.cfg | SmartProS.sh |
| **Miyoo Pixel2**     | 64-bit (ARMv8) | Pixel2.cfg    | Pixel2.sh    |
| **TrimUI Brick**     | 64-bit (ARMv8) | Brick.cfg     | Brick.sh     |

---

## Key Concepts

### Abstraction Layers

**Layer 1: Application Scripts**

- High-level logic (game launching, settings)
- Device-agnostic code

**Layer 2: Platform Abstraction (helperFunctions.sh)**

- Generic helper functions
- Configuration access
- Device detection

**Layer 3: Device-Specific Implementation**

- Hardware control (CPU, display, LED)
- Platform configuration files
- Architecture-specific code

### Configuration System

**Main Config File:** `/mnt/SDCARD/spruce/<PLATFORM>-system.json`

**Configuration Hierarchy:**

1. User's device-specific override
2. User's system-specific preference
3. User's global preference
4. System default (hardcoded)

**Access:** `get_config_value '.path.to.setting.selected'`

### Flag System

**Purpose:** Inter-process communication

**Types:**

- Persistent: `/mnt/SDCARD/spruce/flags/<name>`
- Temporary: `/tmp/<name>`

**Usage:** `flag_add`, `flag_check`, `flag_remove`

### Sourcing Pattern

Most scripts follow this pattern:

```bash
#!/bin/bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh     # Load core
source /mnt/SDCARD/spruce/scripts/platform/device_functions/${PLATFORM}.sh  # Load device-specific

# Now use unified interface - automatically routed!
set_performance     # Works on all devices
vibrate             # Works on all devices
```

---

## Common Patterns

### Reading Configuration

```bash
SWAP_SIZE=$(get_config_value '.menuOptions.System.swapfileSize.selected')
```

### Detecting Device

```bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
echo "Device: $PLATFORM"
```

### Device-Specific Code

```bash
case "$PLATFORM" in
    A30|MiyooMini)
        # 32-bit specific code
        ;;
    Flip|SmartPro)
        # 64-bit specific code
        ;;
esac
```

### Controlling CPU

```bash
set_performance     # Gaming mode
set_smart           # Balanced mode
set_powersave       # Power saving mode
set_overclock       # Maximum performance (A30 only)
```

### Launching Games

```bash
# Games are launched via: /Emu/<SYSTEM>/launch.sh
/Emu/GB/launch.sh "/mnt/SDCARD/Roms/GB/Tetris.gb"
```

---

## File Locations Reference

| Path                                        | Contents                      |
| ------------------------------------------- | ----------------------------- |
| `/mnt/SDCARD/spruce/scripts/`               | All scripts (this directory)  |
| `/mnt/SDCARD/spruce/<PLATFORM>-system.json` | Configuration settings        |
| `/mnt/SDCARD/Emu/`                          | Emulator installations        |
| `/mnt/SDCARD/Roms/`                         | Game ROMs organized by system |
| `/mnt/SDCARD/Saves/`                        | Game saves and configurations |
| `/mnt/SDCARD/Themes/`                       | UI themes                     |
| `/var/log/messages`                         | System kernel log             |
| `/mnt/SDCARD/Saves/spruce/spruce.log`       | SpruceOS application log      |

---

## Getting Help

### Check Script Comments

Most scripts have comments at the top explaining their purpose:

```bash
head -50 /mnt/SDCARD/spruce/scripts/script.sh
```

### View Script Source

To understand a function, look at its implementation:

```bash
grep -A 20 "function_name()" /mnt/SDCARD/spruce/scripts/script.sh
```

### Check Logs

```bash
# System events
tail -f /var/log/messages

# SpruceOS events
tail -f /mnt/SDCARD/Saves/spruce/spruce.log
```

### Common Debug Commands

```bash
# Check device type
source helperFunctions.sh && echo $PLATFORM

# Check if service is running
ps aux | grep servicename

# Check configuration
jq '.menuOptions' /mnt/SDCARD/spruce/<PLATFORM>-system.json | head -50

# Test function
source helperFunctions.sh && get_config_value '.theme'
```

---

## Version Information

This documentation corresponds to SpruceOS with:

- **Supported Devices:** 7 handheld devices
- **Script Count:** 60+ shell scripts
- **Emulator Support:** 40+ systems via RetroArch + specialized emulators
- **Network Services:** 5 (SSH, Samba, Syncthing, SFTPGo, Darkhttpd)
- **Architecture Support:** 32-bit and 64-bit ARM

---

## Document Navigation

```
README.md
├── Overview of all scripts
├── Directory structure
├── Process flows
└── Cross-script communication

ENVIRONMENT_VARIABLES.md
├── All variable types
├── Hardware paths
├── Button mappings
└── Usage patterns

FUNCTIONS.md
├── Helper functions
├── Device control
├── Emulator functions
├── Network functions
└── All function signatures

PLATFORM_ABSTRACTION.md
├── Device detection
├── Architecture overview
├── Creating new platform support
└── Hardware capability matrix

EMULATOR_SYSTEM.md
├── Game launch flow
├── Emulator-specific handlers
├── Configuration system
└── Adding new emulators

NETWORK_SERVICES.md
├── Service descriptions
├── Configuration
├── Usage examples
└── Troubleshooting
```

---

## Tips & Tricks

### Quick Device Detection

```bash
source /mnt/SDCARD/spruce/scripts/helperFunctions.sh
echo "I'm running on: $PLATFORM ($BRAND)"
```

### List All Available Functions

```bash
grep -h "^[a-z_]*() {" /mnt/SDCARD/spruce/scripts/*.sh
```

### Find Function Definition

```bash
grep -r "function_name()" /mnt/SDCARD/spruce/scripts/
```

### Check if Function Exists

```bash
declare -f function_name >/dev/null && echo "Function exists"
```

### Debug Script Execution

```bash
bash -x /path/to/script.sh        # Trace execution
bash -x -e /path/to/script.sh     # Exit on error
```

---

## Contributing & Maintenance

### Before Modifying Scripts

1. Read relevant documentation
2. Understand the abstraction layers
3. Test on multiple devices if possible
4. Update documentation if behavior changes

### Best Practices

1. Source `helperFunctions.sh` first
2. Use `$PLATFORM` and `$SYSTEM_JSON` variables
3. Leverage existing functions instead of duplicating code
4. Log important events using logging functions
5. Use flag system for inter-process communication
6. Handle cleanup on exit

### Adding New Documentation

1. Keep sections focused and organized
2. Provide examples for each concept
3. Reference other documentation files
4. Update this index if adding new files
